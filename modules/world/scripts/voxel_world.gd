class_name VoxelWorld
extends Node3D
## Smooth, diggable voxel terrain (Voxel Tools' VoxelLodTerrain with Transvoxel meshing)
## generated from TerrainHeights.

const SHADER := "res://modules/world/shaders/terrain.gdshader"
const VOXEL_REQUIRED := {"view_distance": TYPE_FLOAT, "lod_count": TYPE_FLOAT, "lod_distance": TYPE_FLOAT, "depth": TYPE_FLOAT, "max_dig_depth": TYPE_FLOAT}

## A hole was dug (after clamping), so grass over it can go.
signal dug(center: Vector3, radius: float)

@export_file("*.json") var config_path: String = "res://modules/world/data/world.json"

var heights: TerrainHeights
var terrain: VoxelLodTerrain
var max_dig_depth := 3.0

var _tool: VoxelTool


func _ready() -> void:
	var data: Variant = Data.load_json(config_path)
	if not data is Dictionary or not Data.require(config_path, data, TerrainHeights.REQUIRED):
		return
	var world: Dictionary = data
	if not world.has("voxel") or not Data.require(config_path + " voxel", world["voxel"], VOXEL_REQUIRED):
		return
	var cfg: Dictionary = world["voxel"]
	heights = TerrainHeights.new(world)
	max_dig_depth = cfg["max_dig_depth"]
	# Other modules place things on the ground where no terrain is loaded to raycast
	# against (the server only streams near players): `ground_height` answers anywhere.
	add_to_group(&"ground")

	terrain = VoxelLodTerrain.new()
	terrain.name = "VoxelTerrain"
	terrain.generator = VoxelHeightGenerator.new(heights)
	terrain.mesher = VoxelMesherTransvoxel.new()
	var half := int(heights.size / 2.0)
	var depth := int(cfg["depth"])
	terrain.voxel_bounds = AABB(Vector3(-half, -depth, -half), Vector3(half * 2, depth * 2, half * 2))
	terrain.view_distance = int(cfg["view_distance"])
	terrain.lod_count = int(cfg["lod_count"])
	terrain.lod_distance = cfg["lod_distance"]
	terrain.generate_collisions = true
	terrain.collision_lod_count = 1
	terrain.material = _terrain_material()
	add_child(terrain)
	_tool = terrain.get_voxel_tool()
	_tool.channel = VoxelBuffer.CHANNEL_SDF
	# Voxel Tools only streams terrain around viewers. This one keeps the spawn area loaded
	# before any player exists (and in tests); players carry their own.
	var viewer := VoxelViewer.new()
	viewer.name = "SpawnViewer"
	viewer.view_distance = int(cfg["view_distance"])
	add_child(viewer)


## CC0 ambientCG texture sets (see assets/LICENSES.md); the server never renders, so it
## skips loading them.
func _terrain_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER)
	if DisplayServer.get_name() == "headless":
		return mat
	var data: Dictionary = Data.load_json(config_path)
	if data.has("biomes") and Data.require(config_path + " biomes", data["biomes"], Biomes.REQUIRED):
		mat.set_shader_parameter("biome_map", Biomes.new(data["biomes"]).bake(heights.size))
		mat.set_shader_parameter("world_size", heights.size)
	# The untouched ground height, so anything dug below it shows as bare dirt.
	mat.set_shader_parameter("ground_map", heights.bake(int(heights.size)))
	mat.set_shader_parameter("ground_size", heights.size)
	for layer in [["grass", "Grass004"], ["dirt", "Ground037"], ["rock", "Rock030"]]:
		var base := "res://modules/world/textures/%s/%s_1K-JPG_" % [layer[1], layer[1]]
		mat.set_shader_parameter(layer[0] + "_albedo", load(base + "Color.jpg"))
		mat.set_shader_parameter(layer[0] + "_normal", load(base + "NormalGL.jpg"))
		mat.set_shader_parameter(layer[0] + "_rough", load(base + "Roughness.jpg"))
	return mat


## A viewer for a player, so terrain streams in around them as they move.
func make_viewer() -> VoxelViewer:
	var viewer := VoxelViewer.new()
	viewer.name = "VoxelViewer"
	viewer.view_distance = terrain.view_distance if terrain != null else 128
	return viewer


## For captures and harnesses: adds the world scene under `parent` and waits until the
## spawn area has collision, so nothing dropped in falls through terrain still streaming.
static func add_and_wait(parent: Node, scene_path: String, max_frames: int = 900) -> Node3D:
	var world: Node3D = (load(scene_path) as PackedScene).instantiate()
	parent.add_child(world)
	var voxels: VoxelWorld = world.get_node("Terrain")
	for i in max_frames:
		if voxels.is_ready_at(Vector3.ZERO):
			break
		await parent.get_tree().physics_frame
	return world


## True once the area around `point` has meshes (and collision) at full detail.
func is_ready_at(point: Vector3, radius: float = 8.0) -> bool:
	if terrain == null:
		return false
	var r := Vector3.ONE * radius
	return terrain.is_area_meshed(AABB(point - r, r * 2.0), 0)


## Carves a smooth sphere out of the terrain. Runs on the server and on every client from
## the same replayed event, so all of them dig the same hole. Never deeper than
## `max_dig_depth` under the untouched ground: explosions stacked in one spot used to dig a
## well nobody could climb out of.
func server_dig(at: Vector3, radius: float) -> void:
	if _tool == null:
		return
	var floor_y := ground_height(at.x, at.z) - max_dig_depth
	var center := Vector3(at.x, maxf(at.y, floor_y + radius), at.z)
	_tool.mode = VoxelTool.MODE_REMOVE
	_tool.do_sphere(center, radius)
	dug.emit(center, radius)


## Height of the untouched ground (ignores digging) for placing spawns and scenery.
func ground_height(x: float, z: float) -> float:
	return heights.height_at(x, z) if heights != null else 0.0
