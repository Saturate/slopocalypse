extends Node3D
## Capture setup: the car pulls away from where it waits outside the start tunnel and drives
## down the road, weaving a little, seen from its own chase camera.

const WORLD := "res://modules/world/scenes/world.tscn"
const CAR := "res://modules/car/scenes/box_car.tscn"

var _car: CarController
var _driver := Node3D.new()
var _ticks := 0
var _road: RoadPath


func _ready() -> void:
	# Voxel terrain streams in; wait for the spawn area before dropping anything onto it.
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	_road = (world.get_node("Terrain") as VoxelWorld).heights.road
	_car = (load(CAR) as PackedScene).instantiate()
	add_child(_car)
	_car.global_transform = (world.get_node("CarSpawn") as Marker3D).global_transform
	add_child(_driver)
	_car.camera().current = true


func _physics_process(_delta: float) -> void:
	if _car == null:
		return
	_ticks += 1
	if _ticks == 30:
		_driver.global_position = _car.global_position
		_car.enter(_driver)
	var intent := _car.intent()
	intent.throttle = 1.0 if _ticks > 30 else 0.0
	# Follow the road: steer towards a point on it a little way ahead, weaving gently.
	var ahead_z := _car.global_position.z - 14.0
	var target := Vector3(_road.x_at(ahead_z) + 1.8 * sin(_ticks / 50.0), 0.0, ahead_z)
	var to := target - _car.global_position
	var nose := _car.global_transform.basis.z
	var angle := atan2(nose.cross(to).y, nose.dot(to))
	# Positive steer turns right (towards -X when facing -Z); `angle` is positive to the left.
	intent.steer = clampf(-angle * 2.0, -1.0, 1.0)
