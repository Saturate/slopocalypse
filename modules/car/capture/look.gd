extends Node3D
## Capture setup: the voxel car parked on the road outside the start tunnel, seen from the
## front quarter, the side, the back quarter, above, the driver's door, and the wheels close up.

const WORLD := "res://modules/world/scenes/world.tscn"
const CAR := "res://modules/car/scenes/box_car.tscn"
const FRAMES_PER_SHOT := 120
## Camera spots around the car, in the car's frame (nose +Z), and where each looks.
const SHOTS := [
	[Vector3(4.0, 1.8, 5.0), Vector3(0.0, 0.8, 0.0)],
	[Vector3(6.5, 1.4, 0.0), Vector3(0.0, 0.8, 0.0)],
	[Vector3(-4.0, 2.0, -5.5), Vector3(0.0, 0.8, 0.0)],
	[Vector3(0.5, 7.0, -2.0), Vector3(0.0, 0.5, 0.0)],
	[Vector3(3.0, 1.6, 1.5), Vector3(0.0, 1.1, 0.0)],
	[Vector3(2.4, 0.6, 3.0), Vector3(0.8, 0.0, 1.35)],
]

var _car: CarController
var _camera := Camera3D.new()
var _ticks := 0
var _current := -1


func _ready() -> void:
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	_car = (load(CAR) as PackedScene).instantiate()
	add_child(_car)
	_car.global_transform = (world.get_node("CarSpawn") as Marker3D).global_transform
	_camera.fov = 60.0
	add_child(_camera)
	_camera.current = true
	_camera.add_child((world.get_node("Terrain") as VoxelWorld).make_viewer())


func _process(_delta: float) -> void:
	if _car == null:
		return
	_ticks += 1
	var shot := (_ticks + FRAMES_PER_SHOT / 2) / FRAMES_PER_SHOT - 1
	if shot == _current or shot < 0 or shot >= SHOTS.size():
		return
	_current = shot
	_camera.global_position = _car.to_global(SHOTS[shot][0])
	_camera.look_at(_car.to_global(SHOTS[shot][1]))
