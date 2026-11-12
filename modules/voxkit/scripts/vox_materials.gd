class_name VoxMaterials
extends RefCounted
## The voxel materials (wood, glass, concrete...) from `materials.json`: each voxel of a model
## stores its material's position in that list, and the entry says how it takes hits. Like
## `VoxShading`, it finds the `Data` autoload at run time, so `-s` tools without autoloads can
## still build models (there it reads the file directly).

const CONFIG := "res://modules/voxkit/data/materials.json"
const FIELDS := {
	"name": TYPE_STRING,
	"bullet": TYPE_FLOAT,
	"blast": TYPE_FLOAT,
	"min_bullet_damage": TYPE_FLOAT,
	"hole": TYPE_FLOAT,
	"pass": TYPE_FLOAT,
	"thickness_max": TYPE_FLOAT,
	"breaks_whole": TYPE_BOOL,
	"hits_to_break": TYPE_FLOAT,
	"crack": TYPE_BOOL,
	"crack_opacity": TYPE_FLOAT,
}

static var _list: Array[Dictionary] = []
static var _index: Dictionary[String, int] = {}


## Every material, in index order.
static func all() -> Array[Dictionary]:
	_ensure()
	return _list


## The index stored in voxels for `name`; 0 (default) for an unknown name, with an error.
static func index_of(name: String) -> int:
	_ensure()
	if not _index.has(name):
		push_error("%s: no material named '%s'" % [CONFIG, name])
		return 0
	return _index[name]


## The entry for index `i`, or the default entry for an index the file doesn't have.
static func at(i: int) -> Dictionary:
	_ensure()
	if _list.is_empty():
		return {}
	return _list[i] if i >= 0 and i < _list.size() else _list[0]


## The entry for `name`.
static func named(name: String) -> Dictionary:
	return at(index_of(name))


## For tests: entries checked the way the file is, true when all are good.
static func validate(entries: Array) -> bool:
	var ok := entries.size() > 0
	var data := _data_node()
	for i in entries.size():
		var e: Variant = entries[i]
		if not e is Dictionary:
			push_error("%s: material %d is not an object" % [CONFIG, i])
			ok = false
			continue
		if data != null:
			ok = bool(data.call(&"require", "%s material %d" % [CONFIG, i], e, FIELDS)) and ok
		else:
			for f: String in FIELDS:
				if typeof((e as Dictionary).get(f)) != FIELDS[f]:
					push_error("%s: material %d needs '%s'" % [CONFIG, i, f])
					ok = false
	return ok


static func _ensure() -> void:
	if not _list.is_empty():
		return
	var data := _data_node()
	var raw: Variant = data.call(&"load_json", CONFIG) if data != null else JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	var entries: Variant = (raw as Dictionary).get("materials") if raw is Dictionary else null
	if not entries is Array or not validate(entries):
		push_error("%s: needs a `materials` list of entries with %s" % [CONFIG, ", ".join(FIELDS.keys())])
		return
	for e: Dictionary in entries:
		_index[str(e["name"])] = _list.size()
		_list.append(e)


static func _data_node() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("Data") if tree != null else null
