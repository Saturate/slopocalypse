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
	"set": "path, property, value (a Godot value string, e.g. Vector3(0, 2, 0))",
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

var token := ""
var role := ""
## Where this process logs (for `log`).
var log_path := ""


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
		"set":
			return _set_property(tree, params)
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


func _state(tree: SceneTree) -> Dictionary:
	var players: Array = []
	for p: Node in tree.get_nodes_in_group(&"players"):
		var entry := {"path": str(p.get_path()), "name": str(p.name)}
		if p is Node3D:
			entry["position"] = var_to_str((p as Node3D).global_position)
		players.append(entry)
	var modules: Array = []
	var holder := tree.root.get_node_or_null("Boot/Modules")
	if holder != null:
		modules = holder.get_children().map(func(m: Node) -> String: return str(m.name))
	var perf := tree.get_first_node_in_group(&"perf_api")
	var mp := tree.root.multiplayer
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
