class_name VoxShading
extends RefCounted
## Corner shading for every voxel mesh: face corners darken by how many voxels crowd them, so
## cracks, inside corners and holes read as shape at any distance. Baked into the meshes'
## vertex colours (no cost per frame). Values from `voxkit.json` (`corner_shading`): `on`,
## and `levels`, the brightness of a corner at each level from 0 (tucked into an inside
## corner) to 3 (open).

const CONFIG := "res://modules/voxkit/data/voxkit.json"

static var _done := false
## The brightness per corner level now in use (empty when off), for GPU volumes that shade
## their corners in the shader instead.
static var levels := PackedFloat32Array()


## Loads the settings once; call before making voxel meshes. Cheap after the first call.
## Finds the `Data` autoload at run time rather than naming it, so scripts run without
## autoloads (`-s` tools) can still use the voxel kit; there it reads the file directly.
static func ensure() -> void:
	if _done:
		return
	_done = true
	var tree := Engine.get_main_loop() as SceneTree
	var data_node: Node = tree.root.get_node_or_null("Data") if tree != null else null
	var data: Variant = data_node.call(&"load_json", CONFIG) if data_node != null else JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	var cfg: Variant = (data as Dictionary).get("corner_shading") if data is Dictionary else null
	if not cfg is Dictionary or not cfg.get("on") is bool or not cfg.get("levels") is Array:
		push_error("%s: needs corner_shading with `on` (true or false) and `levels` (4 numbers)" % CONFIG)
		return
	var levels := PackedFloat32Array()
	if bool(cfg["on"]):
		for v: Variant in cfg["levels"]:
			levels.append(float(v))
		if levels.size() != 4:
			push_error("%s: corner_shading.levels needs 4 numbers" % CONFIG)
			levels.clear()
	VoxShading.levels = levels
	VoxelModel.set_corner_shading(levels)


## For tests and comparison captures: shading on (with `levels`) or off (empty), whatever the
## data says, until `reset()`.
static func force(with: PackedFloat32Array) -> void:
	_done = true
	levels = with
	VoxelModel.set_corner_shading(with)


static func reset() -> void:
	_done = false
	ensure()
