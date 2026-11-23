class_name ModuleLoader
extends RefCounted
## Finds modules/*/module.json, orders modules by dependency and decides which load.
## A module loads when its flag is on (or it has none) and every dependency loads.
##
## Besides `id`, `depends_on`, `flag` and `entry`, a manifest may declare what other parts of
## the game reach in it, so they go with its folder (docs/decisions/0019):
## - `debug_calls`: methods on its entry node the debug API's `call` may run, e.g.
##   `["server_state", "lit_of"]` (reached as "<id>:<method>").
## - `settings`: player settings it reads, each `{key, type, default, label, order}`. The
##   settings screen shows them in its toggle list, by `order`, while the module's flag is on.

const ROOT := "res://modules"
## Setting types a module may register, and the Variant type each holds.
const SETTING_TYPES := {"bool": TYPE_BOOL}


class ModuleInfo:
	var id: StringName
	var dir: String
	var depends_on: Array[StringName] = []
	## Empty means the module has no flag and always loads.
	var flag: StringName = &""
	var entry: String
	var debug_calls: Array[String] = []
	## {key, type, default, label, order}, checked.
	var settings: Array[Dictionary] = []


static func discover(root: String) -> Array[ModuleInfo]:
	var found: Array[ModuleInfo] = []
	for name in DirAccess.get_directories_at(root):
		var dir := root.path_join(name)
		var manifest := dir.path_join("module.json")
		if not FileAccess.file_exists(manifest):
			continue
		var data: Variant = Data.load_json(manifest)
		if data is Dictionary:
			var info := parse_manifest(dir, data)
			if info != null:
				found.append(info)
	return found


static func parse_manifest(dir: String, data: Dictionary) -> ModuleInfo:
	var path := dir.path_join("module.json")
	var fields := {"id": TYPE_STRING, "depends_on": TYPE_ARRAY, "flag": TYPE_STRING, "entry": TYPE_STRING}
	if not Data.require(path, data, fields):
		return null
	var info := ModuleInfo.new()
	info.id = StringName(data["id"])
	info.dir = dir
	info.flag = StringName(data["flag"])
	info.entry = data["entry"]
	for dep: Variant in data["depends_on"]:
		info.depends_on.append(StringName(str(dep)))
	if not _parse_debug_calls(path, data.get("debug_calls", []), info):
		return null
	if not _parse_settings(path, data.get("settings", []), info):
		return null
	return info


static func _parse_debug_calls(path: String, raw: Variant, info: ModuleInfo) -> bool:
	if not raw is Array:
		Log.error(&"data", "%s: field 'debug_calls' should be an array of method names" % path)
		return false
	for m: Variant in raw:
		# A leading _ is engine or private; DebugHandler also refuses anything the module's
		# own script does not declare (call, set, free...).
		if not m is String or not (m as String).is_valid_identifier() or (m as String).begins_with("_"):
			Log.error(&"data", "%s: debug_calls entry %s is not a public method name" % [path, var_to_str(m)])
			return false
		if info.debug_calls.has(m):
			Log.error(&"data", "%s: debug_calls lists '%s' twice" % [path, m])
			return false
		info.debug_calls.append(m)
	return true


static func _parse_settings(path: String, raw: Variant, info: ModuleInfo) -> bool:
	if not raw is Array:
		Log.error(&"data", "%s: field 'settings' should be an array" % path)
		return false
	for entry: Variant in raw:
		if not entry is Dictionary:
			Log.error(&"data", "%s: settings entry %s should be an object" % [path, var_to_str(entry)])
			return false
		var s: Dictionary = entry
		if not Data.require(path, s, {"key": TYPE_STRING, "type": TYPE_STRING, "label": TYPE_STRING, "order": TYPE_FLOAT}):
			return false
		var key: String = s["key"]
		if not key.is_valid_identifier():
			Log.error(&"data", "%s: setting key '%s' should be a plain name" % [path, key])
			return false
		# The label is the toggle's node name too; Godot rewrites . : @ / % " in node names.
		if str(s["label"]).is_empty() or str(s["label"]).validate_node_name() != s["label"]:
			Log.error(&"data", "%s: setting '%s' label '%s' may not be empty or hold . : @ / %% \"" % [path, key, s["label"]])
			return false
		if not SETTING_TYPES.has(s["type"]):
			Log.error(&"data", "%s: setting '%s' has type '%s'; known: %s" % [path, key, s["type"], ", ".join(SETTING_TYPES.keys())])
			return false
		if not s.has("default") or typeof(s["default"]) != SETTING_TYPES[s["type"]]:
			Log.error(&"data", "%s: setting '%s' needs a default of type %s" % [path, key, s["type"]])
			return false
		info.settings.append({"key": key, "type": s["type"], "default": s["default"], "label": s["label"], "order": s["order"]})
	return true


## Returns the modules that should load, dependencies first. Skips are logged with the reason.
static func resolve(modules: Array[ModuleInfo], is_enabled: Callable) -> Array[ModuleInfo]:
	var by_id: Dictionary[StringName, ModuleInfo] = {}
	for m in modules:
		by_id[m.id] = m
	var order: Array[ModuleInfo] = []
	var state: Dictionary[StringName, bool] = {}  # id -> loads?
	var visiting: Dictionary[StringName, bool] = {}
	for m in modules:
		_visit(m, by_id, is_enabled, order, state, visiting)
	return order


static func _visit(
	m: ModuleInfo,
	by_id: Dictionary[StringName, ModuleInfo],
	is_enabled: Callable,
	order: Array[ModuleInfo],
	state: Dictionary[StringName, bool],
	visiting: Dictionary[StringName, bool],
) -> bool:
	if state.has(m.id):
		return state[m.id]
	if visiting.has(m.id):
		Log.error(&"modules", "dependency cycle involving '%s'" % m.id)
		return false
	visiting[m.id] = true
	var loads := true
	if m.flag != &"" and not is_enabled.call(m.flag):
		Log.info(&"modules", "skipped '%s': flag '%s' is off" % [m.id, m.flag])
		loads = false
	else:
		for dep in m.depends_on:
			if not by_id.has(dep):
				Log.info(&"modules", "skipped '%s': depends on '%s', which is not present" % [m.id, dep])
				loads = false
				break
			if not _visit(by_id[dep], by_id, is_enabled, order, state, visiting):
				Log.info(&"modules", "skipped '%s': depends on '%s', which is not loaded" % [m.id, dep])
				loads = false
				break
	visiting.erase(m.id)
	state[m.id] = loads
	if loads:
		order.append(m)
	return loads
