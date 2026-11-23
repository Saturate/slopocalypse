extends Node3D
## Capture setup: the car pulls away from where it waits by the camp and drives down the
## highway, weaving a little, seen from its own chase camera.

const WORLD := "res://modules/world/scenes/world.tscn"
const CAR := "res://modules/car/scenes/box_car.tscn"

var _car: CarController
var _driver := Node3D.new()
var _ticks := 0
var _voxels: VoxelWorld
## Metres along the highway of the point the car steers for, and the highway's length.
var _along := 0.0
var _end := 0.0


func _ready() -> void:
	# Voxel terrain streams in; wait for the spawn area before dropping anything onto it.
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	_voxels = world.get_node("Terrain") as VoxelWorld
	var points := WorldMaps.shape_or_default().highway()
	for k in range(1, points.size()):
		_end += points[k].distance_to(points[k - 1])
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
	while _voxels.road_point(_along).distance_to(_car.global_position) < 14.0 and _along < _end:
		_along += 1.0
	var centre := _voxels.road_point(_along)
	var along := _voxels.road_point(_along + 1.0) - centre
	var right := along.normalized().cross(Vector3.UP) if along.length() > 0.001 else Vector3.RIGHT
	var target := centre + right * 1.8 * sin(_ticks / 50.0)
	var to := target - _car.global_position
	to.y = 0.0
	var nose := _car.global_transform.basis.z
	var angle := atan2(nose.cross(to).y, nose.dot(to))
	# Positive steer turns right (towards -X when facing -Z); `angle` is positive to the left.
	intent.steer = clampf(-angle * 2.0, -1.0, 1.0)
