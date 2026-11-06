class_name ModuleLoader
extends RefCounted
## Finds modules/*/module.json, orders modules by dependency and decides which load.
## A module loads when its flag is on (or it has none) and every dependency loads.


class ModuleInfo:
	var id: StringName
	var dir: String
	var depends_on: Array[StringName] = []
	## Empty means the module has no flag and always loads.
	var flag: StringName = &""
	var entry: String


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
	return info


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
