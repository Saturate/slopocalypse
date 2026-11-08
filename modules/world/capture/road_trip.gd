extends Node3D
## Capture setup: six stops down the road (spawn, forest, meadow, dry, rocky hills, the far
## end), each looking along it from just above, for judging the road and the biomes.

const WORLD := "res://modules/world/scenes/world.tscn"
const STOPS := [10.0, 450.0, 1000.0, 1600.0, 2300.0, 2850.0]
const FRAMES_PER_STOP := 150

var _camera := Camera3D.new()
var _heights: TerrainHeights
var _scatter: SceneryScatter
var _ticks := 0


func _ready() -> void:
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	_heights = (world.get_node("Terrain") as VoxelWorld).heights
	_scatter = world.get_node("Scenery")
	_camera.fov = 70.0
	_camera.far = 900.0
	add_child(_camera)
	_camera.current = true
	_camera.add_child((world.get_node("Terrain") as VoxelWorld).make_viewer())
	_go(0)


func _process(_delta: float) -> void:
	if _heights == null:
		return
	_ticks += 1
	if _ticks % FRAMES_PER_STOP == 0:
		_go(_ticks / FRAMES_PER_STOP)


func _go(stop: int) -> void:
	if stop >= STOPS.size():
		return
	var z := -float(STOPS[stop])
	var road := _heights.road
	var at := Vector3(road.x_at(z) + 6.0, road.height_at(z) + 5.0, z)
	var ahead := Vector3(road.x_at(z - 60.0), road.height_at(z - 60.0) + 1.0, z - 60.0)
	_camera.global_position = at
	_camera.look_at(ahead)
	# Build everything around the new spot at once instead of a chunk a frame.
	_scatter.update_around([at], INF)
