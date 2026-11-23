extends Node3D
## Capture setup: six stops along the highway from the camp (past its end, the last stops
## stand at the end), each looking along it from just above, for judging the road and the
## biomes.

const WORLD := "res://modules/world/scenes/world.tscn"
const STOPS := [10.0, 250.0, 500.0, 800.0, 1100.0, 1400.0]
const FRAMES_PER_STOP := 150

var _camera := Camera3D.new()
var _voxels: VoxelWorld
var _scatter: SceneryScatter
var _ticks := 0


func _ready() -> void:
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	_voxels = world.get_node("Terrain") as VoxelWorld
	_scatter = world.get_node("Scenery")
	_camera.fov = 70.0
	_camera.far = 900.0
	add_child(_camera)
	_camera.current = true
	_camera.add_child((world.get_node("Terrain") as VoxelWorld).make_viewer())
	_go(0)


func _process(_delta: float) -> void:
	if _voxels == null:
		return
	_ticks += 1
	if _ticks % FRAMES_PER_STOP == 0:
		_go(_ticks / FRAMES_PER_STOP)


func _go(stop: int) -> void:
	if stop >= STOPS.size():
		return
	var m := float(STOPS[stop])
	var centre := _voxels.road_point(m)
	var along := _voxels.road_point(m + 1.0) - centre
	along.y = 0.0
	var right := along.normalized().cross(Vector3.UP) if along.length() > 0.001 else Vector3.RIGHT
	var at := centre + right * 6.0 + Vector3.UP * 5.0
	var ahead := _voxels.road_point(m + 60.0) + Vector3.UP * 1.0
	_camera.global_position = at
	_camera.look_at(ahead)
	# Build everything around the new spot at once instead of a chunk a frame.
	_scatter.update_around([at], INF)
	_voxels.update_around([at], INF)
