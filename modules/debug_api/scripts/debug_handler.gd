class_name DebugHandler
extends RefCounted
## The debug API's requests: HTTP parsing and what each method does. No sockets here, so it
## is tested on its own; the module owns the listener.

## Methods and what they take, for errors and for tools listing them.
const METHODS := {
	"ping": "",
	"state": "",
	"perf": "",
	"find_nodes": "pattern (matches node name or path, * and ? wildcards), type (class name, optional), limit",
	"node": "path",
	"get": "path, property (any property, script variables too)",
	"set": "path, property, value (a Godot value string, e.g. Vector3(0, 2, 0))",
	"call": "target (<module>:<method>, a method in that module's module.json debug_calls), args (Godot value strings; a NodePath is passed as the node there)",
	"setting": "key (a setting a module that is on registers in its module.json), value (JSON, the setting's own type); this process only, never saved",
	"publish": "topic, payload (object)",
	"screenshot": "",
	"log": "lines",
}
const DEFAULT_LIMIT := 50
## Nodes listed per find at most, so a pattern of * does not return the whole tree.
const MAX_LIMIT := 500
## Longest stored value shown per property before it is cut short.
const MAX_VALUE_CHARS := 400
## Biggest request body accepted.
const MAX_BODY := 65536
## Values `get` and `call` return are cut to this many elements per container.
const MAX_ITEMS := 200
## Arguments a call takes at most.
const MAX_ARGS := 8

var token := ""
var role := ""
## Where this process logs (for `log`).
var log_path := ""
## Where `call` targets are found; tests point it elsewhere.
var modules_path := "/root/Boot/Modules"
## The only methods `call` reaches, as "<module>:<method>": each module lists its own in its
## module.json (`debug_calls`), so the list goes with the module's folder. Each is a module's
## public API that playtests (tools/play.ts) need and no property or event reaches. A list,
## not any method on any node: `set` already changes anything stored, but a free call would
## also reach OS, file and network methods through any node. Tests set their own.
var calls: Array[String] = allowed_calls(ModuleLoader.discover(ModuleLoader.ROOT))


## Parses an HTTP request from the bytes received so far. Returns {complete: false} until
## the headers and the whole body have arrived; then {complete, method, path, headers, body}.
static func parse_request(data: PackedByteArray) -> Dictionary:
	var text := data.get_string_from_utf8()
	var end := text.find("\r\n\r\n")
	if end < 0:
		return {"complete": false}
	var lines := text.substr(0, end).split("\r\n")
	var first := lines[0].split(" ")
	var headers := {}
	for i in range(1, lines.size()):
		var colon := lines[i].find(":")
		if colon > 0:
			headers[lines[i].substr(0, colon).strip_edges().to_lower()] = lines[i].substr(colon + 1).strip_edges()
	var length := int(headers.get("content-length", "0"))
	var body_start := text.substr(0, end + 4).to_utf8_buffer().size()
	if length > MAX_BODY:
		return {"complete": true, "method": first[0], "path": first[1] if first.size() > 1 else "", "headers": headers, "body": "", "too_large": true}
	if data.size() - body_start < length:
		return {"complete": false}
	var body := data.slice(body_start, body_start + length).get_string_from_utf8()
	return {"complete": true, "method": first[0], "path": first[1] if first.size() > 1 else "", "headers": headers, "body": body}


## Status code and JSON reply for a parsed request.
func respond(request: Dictionary, tree: SceneTree) -> Array:
	if request.get("too_large", false):
		return [413, {"error": "request too large"}]
	if request["method"] != "POST" or request["path"] != "/rpc":
		return [404, {"error": "POST /rpc only"}]
	if str(request["headers"].get("authorization", "")) != "Bearer " + token:
		return [401, {"error": "bad or missing token"}]
	# A JSON instance reports bad input as a code; JSON.parse_string would log an engine error.
	var json := JSON.new()
	var call: Variant = json.data if json.parse(request["body"]) == OK else null
	if not call is Dictionary or not (call as Dictionary).has("method"):
		return [400, {"error": "body must be {\"method\": ..., \"params\": {...}}"}]
	var params: Variant = (call as Dictionary).get("params", {})
	if not params is Dictionary:
		return [400, {"error": "params must be an object"}]
	return [200, call_method(str(call["method"]), params, tree)]


## {result: ...} or {error: "..."}.
func call_method(method: String, params: Dictionary, tree: SceneTree) -> Dictionary:
	match method:
		"ping":
			return {"result": {"pid": OS.get_process_id(), "role": role, "version": str(ProjectSettings.get_setting("application/config/version", ""))}}
		"state":
			return {"result": _state(tree)}
		"perf":
			var perf := tree.get_first_node_in_group(&"perf_api")
			return {"result": perf.call(&"latest") if perf != null else {}}
		"find_nodes":
			return {"result": find_nodes(tree.root, str(params.get("pattern", "*")), str(params.get("type", "")), clampi(int(params.get("limit", DEFAULT_LIMIT)), 1, MAX_LIMIT))}
		"node":
			var node := tree.root.get_node_or_null(NodePath(str(params.get("path", ""))))
			if node == null:
				return {"error": "no node at %s" % params.get("path", "")}
			return {"result": describe(node)}
		"get":
			return _get_property(tree, params)
		"set":
			return _set_property(tree, params)
		"call":
			return _call(tree, params)
		"setting":
			return _setting(params)
		"publish":
			var topic := str(params.get("topic", ""))
			if topic.is_empty():
				return {"error": "publish needs a topic"}
			var payload: Variant = params.get("payload", {})
			EventBus.publish(StringName(topic), payload if payload is Dictionary else {})
			return {"result": "published %s" % topic}
		"screenshot":
			return _screenshot(tree)
		"log":
			return _log(int(params.get("lines", 50)))
	return {"error": "unknown method %s; methods: %s" % [method, ", ".join(METHODS.keys())]}


## Nodes under `from` whose name or path matches `pattern`, optionally of class `type`.
static func find_nodes(from: Node, pattern: String, type: String, limit: int) -> Array:
	var out: Array = []
	var stack: Array[Node] = [from]
	while not stack.is_empty() and out.size() < limit:
		var node: Node = stack.pop_back()
		var path := str(node.get_path())
		if (node.name.matchn(pattern) or path.matchn(pattern)) and (type.is_empty() or node.is_class(type)):
			out.append({"path": path, "class": node.get_class()})
		var children := node.get_children()
		children.reverse()
		stack.append_array(children)
	return out


## Class, stored properties (as Godot value strings) and child names of a node.
static func describe(node: Node) -> Dictionary:
	var props := {}
	for prop: Dictionary in node.get_property_list():
		if int(prop["usage"]) & PROPERTY_USAGE_STORAGE == 0:
			continue
		var text := var_to_str(node.get(prop["name"]))
		props[prop["name"]] = text if text.length() <= MAX_VALUE_CHARS else text.substr(0, MAX_VALUE_CHARS) + "..."
	var out := {"path": str(node.get_path()), "class": node.get_class(), "properties": props, "children": node.get_children().map(func(c: Node) -> String: return str(c.name))}
	if node.get_script() != null:
		out["script"] = (node.get_script() as Script).resource_path
	if node is Node3D and node.is_inside_tree():
		out["global_position"] = var_to_str((node as Node3D).global_position)
	return out


func _set_property(tree: SceneTree, params: Dictionary) -> Dictionary:
	var node := tree.root.get_node_or_null(NodePath(str(params.get("path", ""))))
	if node == null:
		return {"error": "no node at %s" % params.get("path", "")}
	var property := str(params.get("property", ""))
	if not property in node:
		return {"error": "%s has no property %s" % [node.get_class(), property]}
	var value: Variant = str_to_var(str(params.get("value", "")))
	node.set(property, value)
	return {"result": "%s.%s = %s" % [node.get_path(), property, var_to_str(node.get(property))]}


func _get_property(tree: SceneTree, params: Dictionary) -> Dictionary:
	var node := tree.root.get_node_or_null(NodePath(str(params.get("path", ""))))
	if node == null:
		return {"error": "no node at %s" % params.get("path", "")}
	var property := str(params.get("property", ""))
	if not property in node:
		return {"error": "%s has no property %s" % [node.get_class(), property]}
	var value: Variant = node.get(property)
	var text := var_to_str(value)
	return {"result": {"text": text if text.length() <= MAX_VALUE_CHARS else text.substr(0, MAX_VALUE_CHARS) + "...", "value": plain(value)}}


## Calls an allow-listed module method (`calls`) with arguments given as Godot value strings.
func _call(tree: SceneTree, params: Dictionary) -> Dictionary:
	var target := str(params.get("target", ""))
	if not calls.has(target):
		return {"error": "%s is not callable; allowed: %s" % [target, ", ".join(calls)]}
	var at := target.rfind(":")
	var node := tree.root.get_node_or_null(NodePath(modules_path.path_join(target.substr(0, at))))
	var method := target.substr(at + 1)
	# A client has the server's methods too; there they would change only its own copy.
	if method.begins_with("server_") and role != "server":
		return {"error": "%s runs on the server only; this is a %s" % [target, role]}
	if node == null or not node.has_method(method):
		return {"error": "%s is not loaded here (module off, or the other side of the session)" % target}
	# Only the module's own script methods: a manifest (or a tweaks/ copy of one) naming an
	# inherited Node method such as `call` or `set_script` would undo the allow-list.
	if not _declared_by_script(node, method):
		return {"error": "%s is not a method the module's script declares" % target}
	var raw: Variant = params.get("args", [])
	if not raw is Array or (raw as Array).size() > MAX_ARGS:
		return {"error": "args must be an array of at most %d Godot value strings" % MAX_ARGS}
	var args: Array = []
	for a: Variant in raw:
		var value: Variant = str_to_var(str(a))
		if value is NodePath:
			var found := tree.root.get_node_or_null(value as NodePath)
			if found == null:
				return {"error": "no node at %s" % value}
			value = found
		args.append(value)
	if args.size() < node.get_method_argument_count(method) - _default_count(node, method) or args.size() > node.get_method_argument_count(method):
		return {"error": "%s takes %d argument(s), got %d" % [target, node.get_method_argument_count(method), args.size()]}
	return {"result": plain(node.callv(method, args))}


## Changes one of this process's settings as the settings screen would (modules hear
## `settings.changed`), without saving it: the playtest's clients share the player's own
## settings file.
func _setting(params: Dictionary) -> Dictionary:
	var key := str(params.get("key", ""))
	# Only what the settings screen offers: module settings of modules that are on. Window,
	# volume and key settings (core's) stay out.
	var offered: Array[String] = []
	for entry in Settings.offered():
		offered.append(str(entry["key"]))
	if not offered.has(key):
		return {"error": "%s is not a setting this API changes; allowed: %s" % [key, ", ".join(offered)]}
	var value: Variant = params.get("value")
	var expected: int = ModuleLoader.SETTING_TYPES[Settings.registered(key)["type"]]
	if typeof(value) != expected:
		return {"error": "%s takes a %s, got %s" % [key, type_string(expected), type_string(typeof(value))]}
	Settings.set_value(key, value)
	return {"result": plain(Settings.value(key))}


static func _declared_by_script(node: Node, method: String) -> bool:
	var script := node.get_script() as Script
	while script != null:
		for m: Dictionary in script.get_script_method_list():
			if m["name"] == method:
				return true
		script = script.get_base_script()
	return false


## "<module>:<method>" for every method the modules' manifests allow.
static func allowed_calls(modules: Array[ModuleLoader.ModuleInfo]) -> Array[String]:
	var out: Array[String] = []
	for m in modules:
		for method in m.debug_calls:
			out.append("%s:%s" % [m.id, method])
	out.sort()
	return out


func _default_count(node: Object, method: String) -> int:
	for m: Dictionary in node.get_method_list():
		if m["name"] == method:
			return (m["default_args"] as Array).size()
	return 0


## A value as plain JSON: vectors and colours as arrays of numbers, containers walked,
## anything else as its Godot value string.
static func plain(value: Variant) -> Variant:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return value
		TYPE_STRING_NAME, TYPE_NODE_PATH:
			return str(value)
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return [value.x, value.y]
		TYPE_VECTOR3, TYPE_VECTOR3I:
			return [value.x, value.y, value.z]
		TYPE_COLOR:
			return [value.r, value.g, value.b, value.a]
		TYPE_DICTIONARY:
			var out := {}
			for k: Variant in value:
				if out.size() >= MAX_ITEMS:
					break
				out[str(k)] = plain(value[k])
			return out
		TYPE_OBJECT:
			# `is` on a freed object is a script error, so validity comes first.
			if not is_instance_valid(value):
				return "<freed>"
			if value is Node:
				return str((value as Node).get_path()) if (value as Node).is_inside_tree() else str((value as Node).name)
			return var_to_str(value)
	if value is Array or typeof(value) >= TYPE_PACKED_BYTE_ARRAY:
		return Array(value).slice(0, MAX_ITEMS).map(func(v: Variant) -> Variant: return plain(v))
	return var_to_str(value)


func _state(tree: SceneTree) -> Dictionary:
	var players: Array = []
	for p: Node in tree.get_nodes_in_group(&"players"):
		var peer := int(p.get_meta(&"peer_id", 0))
		var entry := {"path": str(p.get_path()), "name": str(p.name), "peer_id": peer, "player_name": str(p.get_meta(&"player_name", "")), "dead": bool(p.get_meta(&"dead", false)), "local": Net.has_local_player() and peer == Net.local_peer_id()}
		if p is Node3D:
			entry["position"] = var_to_str((p as Node3D).global_position)
			entry["at"] = plain((p as Node3D).global_position)
		players.append(entry)
	var modules: Array = []
	var holder := tree.root.get_node_or_null("Boot/Modules")
	if holder != null:
		modules = holder.get_children().map(func(m: Node) -> String: return str(m.name))
	var perf := tree.get_first_node_in_group(&"perf_api")
	var mp := tree.root.multiplayer
	# Voxel hashes of the mission buildings, by node name, so a test can check every copy
	# has the same cells.
	var hashes := {}
	for b: Node in tree.get_nodes_in_group(&"mission_buildings"):
		if b.has_method(&"grid_hash"):
			hashes[str(b.name)] = str(b.call(&"grid_hash"))
	return {
		"pid": OS.get_process_id(),
		"role": role,
		"mode": ["solo", "server", "client"][int(Net.mode)],
		"connected": Net.is_session_connected(),
		"peer_id": mp.get_unique_id() if mp.has_multiplayer_peer() else 0,
		"peers": Array(mp.get_peers()) if mp.has_multiplayer_peer() else [],
		"players": players,
		"modules": modules,
		"fps": Engine.get_frames_per_second(),
		"perf": perf.call(&"latest") if perf != null else {},
		"building_hashes": hashes,
	}


func _screenshot(tree: SceneTree) -> Dictionary:
	if DisplayServer.get_name() == "headless":
		return {"error": "a headless process has no screen; ask the client"}
	var image := tree.root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("user://debug")
	var path := "user://debug/shot-%d.png" % Time.get_ticks_msec()
	var err := image.save_png(path)
	if err != OK:
		return {"error": "could not save %s: %s" % [path, error_string(err)]}
	return {"result": {"path": ProjectSettings.globalize_path(path), "width": image.get_width(), "height": image.get_height()}}


func _log(lines: int) -> Dictionary:
	if log_path.is_empty() or not FileAccess.file_exists(log_path):
		return {"error": "no log file for this process"}
	var all := FileAccess.get_file_as_string(log_path).split("\n")
	var count := clampi(lines, 1, 2000)
	return {"result": "\n".join(all.slice(maxi(all.size() - count, 0)))}
