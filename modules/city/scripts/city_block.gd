class_name CityBlock
extends RefCounted
## A hand-made city block (#339): what stands inside its pavement, as data. Each piece is a
## voxel generator from the kit by its class name, with parameters, a place and a turn
## within the block; markers note doors, passages and spawn points. The city takes a block
## for a plot it fits, and generates the rest.
##
## Read straight from the file (no autoloads), so the editor tool can use it too.

const FOLDER := "res://modules/city/data/blocks/"
const MARKER_KINDS: Array[String] = ["door", "passage", "spawn"]

var name := ""
## Metres across x and z, inside the pavement; the block's middle is its origin.
var size := Vector2.ZERO
var tags: Array[String] = []
## Each: {generator: String, params: Dictionary, at: Vector3, yaw: float (degrees), vary: Array}.
var pieces: Array[Dictionary] = []
## Each: {kind: String, at: Vector3, yaw: float}.
var markers: Array[Dictionary] = []


static func names() -> Array[String]:
	var out: Array[String] = []
	for file in DirAccess.get_files_at(FOLDER):
		if file.ends_with(".json"):
			out.append(file.trim_suffix(".json"))
	out.sort()
	return out


static func load_named(block_name: String) -> CityBlock:
	var path := FOLDER + block_name + ".json"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		_error("city block %s: %s is not a JSON object" % [block_name, path])
		return null
	return from_data(parsed, block_name)


## The generators the kit has, by class name.
static func generators() -> Dictionary:
	var out := {}
	for g in VoxCatalog.all():
		out[str(g.get_script().get_global_name())] = g
	return out


## A block from its data, or null (with an error naming it) if anything in it is wrong.
static func from_data(data: Dictionary, block_name: String) -> CityBlock:
	var b := CityBlock.new()
	b.name = str(data.get("name", block_name))
	var s: Variant = data.get("size")
	if not (s is Array and (s as Array).size() == 2):
		_error("city block %s: `size` must be [x, z]" % block_name)
		return null
	b.size = Vector2(float(s[0]), float(s[1]))
	for t: Variant in data.get("tags", []):
		b.tags.append(str(t))
	var kit := generators()
	for i in (data.get("pieces", []) as Array).size():
		var p: Dictionary = data["pieces"][i]
		var gen_name := str(p.get("generator", ""))
		if not kit.has(gen_name):
			_error("city block %s: piece %d uses an unknown generator `%s`" % [block_name, i, gen_name])
			return null
		var known := (kit[gen_name] as VoxGenerator).defaults()
		var params: Dictionary = p.get("params", {})
		for key: Variant in params:
			if not known.has(key):
				_error("city block %s: piece %d (%s) has no parameter `%s`" % [block_name, i, gen_name, key])
				return null
		var at: Array = p.get("at", [0, 0, 0])
		var vary: Array = p.get("vary", [])
		b.pieces.append({"generator": gen_name, "params": params.duplicate(), "at": Vector3(float(at[0]), float(at[1]), float(at[2])), "yaw": float(p.get("yaw", 0.0)), "vary": vary.duplicate()})
	for i in (data.get("markers", []) as Array).size():
		var m: Dictionary = data["markers"][i]
		var kind := str(m.get("kind", ""))
		if not MARKER_KINDS.has(kind):
			_error("city block %s: marker %d has an unknown kind `%s`" % [block_name, i, kind])
			return null
		var at: Array = m.get("at", [0, 0, 0])
		b.markers.append({"kind": kind, "at": Vector3(float(at[0]), float(at[1]), float(at[2])), "yaw": float(m.get("yaw", 0.0))})
	if b.pieces.is_empty():
		_error("city block %s: no pieces" % block_name)
		return null
	return b


func to_data() -> Dictionary:
	var out_pieces: Array = []
	for p in pieces:
		var at: Vector3 = p["at"]
		var entry := {"generator": p["generator"], "params": p["params"], "at": [at.x, at.y, at.z], "yaw": p["yaw"]}
		if not (p["vary"] as Array).is_empty():
			entry["vary"] = p["vary"]
		out_pieces.append(entry)
	var out_markers: Array = []
	for m in markers:
		var at: Vector3 = m["at"]
		out_markers.append({"kind": m["kind"], "at": [at.x, at.y, at.z], "yaw": m["yaw"]})
	return {"name": name, "size": [size.x, size.y], "tags": tags.duplicate(), "pieces": out_pieces, "markers": out_markers}


## Whether a plot `plot` metres across fits this block within `slack` metres each way.
func fits(plot: Vector2, slack: float) -> bool:
	return absf(plot.x - size.x) <= slack and absf(plot.y - size.y) <= slack


func has_tag(tag: String) -> bool:
	return tags.has(tag)


## Through the `Log` autoload where there is one (the game, tests), so a broken block shows
## in the log with its name; the editor has none, so there it is a plain engine error.
static func _error(message: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var log_node := tree.root.get_node_or_null(^"Log") if tree != null else null
	if log_node != null:
		log_node.call(&"error", &"city", message)
	else:
		push_error(message)
