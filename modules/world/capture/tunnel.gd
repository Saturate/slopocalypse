extends Node3D
## Capture setup: the start tunnel. At the spawn looking out of the portal, turned round
## at the cave-in, from the road outside looking back at the portal, from higher up the
## road, from the side over the mountain, and the headwall close up.

const WORLD := "res://modules/world/scenes/world.tscn"
const FRAMES_PER_SHOT := 120

var _camera := Camera3D.new()
var _shots: Array[Array] = []
var _ticks := 0
var _current := 0
var _world: Node3D


func _ready() -> void:
	_world = await VoxelWorld.add_and_wait(self, WORLD)
	var heights := (_world.get_node("Terrain") as VoxelWorld).heights
	var spawn := (_world.get_node("SpawnPoint") as Marker3D).global_position
	var portal: float = heights.start["portal_z"]
	var end: float = heights.start["tunnel_end_z"]
	var floor_y := heights.road.height_at(0.0)
	var eye := Vector3.UP * 0.7
	_shots = [
		[spawn + eye, Vector3(0.0, floor_y + 1.4, portal - 30.0)],
		[Vector3(1.0, floor_y + 1.7, 2.0), Vector3(0.0, floor_y + 1.5, end)],
		[Vector3(2.0, floor_y + 1.7, portal - 22.0), Vector3(0.0, floor_y + 4.0, portal)],
		[Vector3(-6.0, floor_y + 9.0, portal - 60.0), Vector3(0.0, floor_y + 8.0, portal + 10.0)],
		[Vector3(40.0, floor_y + 32.0, portal - 30.0), Vector3(0.0, floor_y + 14.0, 2.0)],
		[Vector3(4.0, floor_y + 1.8, portal - 7.0), Vector3(-1.0, floor_y + 3.0, portal)],
	]
	_camera.fov = 70.0
	_camera.far = 900.0
	add_child(_camera)
	_camera.current = true
	_camera.add_child((_world.get_node("Terrain") as VoxelWorld).make_viewer())
	_go(0)


func _process(_delta: float) -> void:
	if _shots.is_empty():
		return
	_ticks += 1
	# The sheet samples every FRAMES_PER_SHOT frames; switch half a shot before each sample
	# so every shot has had time to load when it is taken.
	var shot := (_ticks + FRAMES_PER_SHOT / 2) / FRAMES_PER_SHOT - 1
	if shot != _current:
		_current = shot
		_go(shot)


func _go(shot: int) -> void:
	if shot >= _shots.size():
		return
	var at: Vector3 = _shots[shot][0]
	_camera.global_position = at
	_camera.look_at(_shots[shot][1])
	(_world.get_node("Scenery") as SceneryScatter).update_around([at], INF)
	(_world.get_node("Terrain") as VoxelWorld).update_around([at], INF)
