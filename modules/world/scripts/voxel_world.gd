class_name VoxelWorld
extends Node3D
## Smooth, diggable voxel terrain (Voxel Tools' VoxelLodTerrain with Transvoxel meshing)
## generated from TerrainHeights. Replaces the old heightmap TerrainChunk.

const SHADER := "res://modules/world/shaders/terrain.gdshader"
const VOXEL_REQUIRED := {"view_distance": TYPE_FLOAT, "lod_count": TYPE_FLOAT, "lod_distance": TYPE_FLOAT, "depth": TYPE_FLOAT}

@export_file("*.json") var config_path: String = "res://modules/world/data/world.json"

var heights: TerrainHeights
var terrain: VoxelLodTerrain

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
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER)
	terrain.material = mat
	add_child(terrain)
	_tool = terrain.get_voxel_tool()
	_tool.channel = VoxelBuffer.CHANNEL_SDF
	# Voxel Tools only streams terrain around viewers. This one keeps the spawn area loaded
	# before any player exists (and in tests); players carry their own.
	var viewer := VoxelViewer.new()
	viewer.name = "SpawnViewer"
	viewer.view_distance = int(cfg["view_distance"])
	add_child(viewer)


## A viewer for a player, so terrain streams in around them as they move.
func make_viewer() -> VoxelViewer:
	var viewer := VoxelViewer.new()
	viewer.name = "VoxelViewer"
	viewer.view_distance = terrain.view_distance if terrain != null else 128
	return viewer


## True once the area around `point` has meshes (and collision) at full detail.
func is_ready_at(point: Vector3, radius: float = 8.0) -> bool:
	if terrain == null:
		return false
	var r := Vector3.ONE * radius
	return terrain.is_area_meshed(AABB(point - r, r * 2.0), 0)


## Server only: carves a smooth sphere out of the terrain.
func server_dig(at: Vector3, radius: float) -> void:
	if _tool == null:
		return
	_tool.mode = VoxelTool.MODE_REMOVE
	_tool.do_sphere(at, radius)


## Height of the untouched ground (ignores digging) for placing spawns and scenery.
func ground_height(x: float, z: float) -> float:
	return heights.height_at(x, z) if heights != null else 0.0
