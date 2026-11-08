extends Node3D
## Capture setup: the same view down the road from beside the tunnel at dawn, morning,
## midday, late afternoon, dusk and midnight.

const WORLD := "res://modules/world/scenes/world.tscn"
const FRAMES_PER_SHOT := 120
const HOURS: Array[float] = [6.4, 9.0, 13.0, 17.6, 19.1, 23.0]

var _camera := Camera3D.new()
var _ticks := 0
var _current := -1
var _world: Node3D
var _clock: DayClock
var _lighting := DayLighting.new()


func _ready() -> void:
	_world = await VoxelWorld.add_and_wait(self, WORLD)
	var heights := (_world.get_node("Terrain") as VoxelWorld).heights
	var portal: float = heights.start["portal_z"]
	_clock = DayClock.from_data()
	add_child(_lighting)
	var env := _world.get_node("Environment") as WorldEnvironment
	_lighting.attach(_world.get_node("Sun") as DirectionalLight3D, env.environment)
	_camera.fov = 70.0
	_camera.far = 900.0
	add_child(_camera)
	_camera.current = true
	var z := portal - 14.0
	var at := Vector3(heights.road.x_at(z), heights.height_at(heights.road.x_at(z), z) + 3.0, z)
	_camera.global_position = at
	var far := portal - 90.0
	_camera.look_at(Vector3(heights.road.x_at(far), at.y + 2.0, far))
	_camera.add_child((_world.get_node("Terrain") as VoxelWorld).make_viewer())
	(_world.get_node("Scenery") as SceneryScatter).update_around([at], INF)
	(_world.get_node("Terrain") as VoxelWorld).update_around([at], INF)
	_go(0)


func _process(_delta: float) -> void:
	if _clock == null:
		return
	_ticks += 1
	var shot := (_ticks + FRAMES_PER_SHOT / 2) / FRAMES_PER_SHOT - 1
	if shot != _current:
		_go(shot)


func _go(shot: int) -> void:
	_current = shot
	if shot < 0 or shot >= HOURS.size():
		return
	_clock.set_hour(HOURS[shot])
	_lighting.apply(_clock)
