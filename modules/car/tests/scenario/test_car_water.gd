extends GdUnitTestSuite
## A car driven into deep water stalls (no power while the front axle is deeper than
## `stall_depth`) and starts again once it is back out; water also holds it back.

const CAR := "res://modules/car/scenes/box_car.tscn"


## Deep water from z 30 on, none before it.
class FakeWater extends Node:
	func _ready() -> void:
		add_to_group(&"ground")

	func water_depth_at(p: Vector3) -> float:
		return 1.2 if p.z > 30.0 else 0.0


var _ground: StaticBody3D
var _car: CarController
var _driver: Node3D


func before_test() -> void:
	_ground = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	_ground.add_child(shape)
	add_child(_ground)
	add_child(auto_free(FakeWater.new()))
	_car = (load(CAR) as PackedScene).instantiate()
	add_child(_car)
	_car.global_position = Vector3(0.0, 1.0, 0.0)
	_driver = auto_free(Node3D.new())
	add_child(_driver)


func after_test() -> void:
	_car.free()
	_ground.free()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _drive_from(z: float) -> float:
	_car.global_position = Vector3(0.0, 1.0, z)
	_car.linear_velocity = Vector3.ZERO
	_car.intent().throttle = 1.0
	await _frames(90)
	return _car.forward_speed()


func test_deep_water_stalls_it_and_it_restarts_once_out() -> void:
	await _frames(60)
	_driver.global_position = _car.global_position
	_car.enter(_driver)
	var dry := await _drive_from(-150.0)
	assert_float(dry).is_greater(5.0)
	assert_bool(_car.stalled).is_false()
	var wet := await _drive_from(60.0)
	assert_bool(_car.stalled).is_true()
	assert_float(_car.engine_force).is_equal(0.0)
	assert_float(absf(wet)).is_less(0.5)
	# Towed back out: power again.
	var again := await _drive_from(-150.0)
	assert_bool(_car.stalled).is_false()
	assert_float(again).is_greater(5.0)
