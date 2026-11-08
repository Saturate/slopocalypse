extends GdUnitTestSuite
## Drives the real box car through CarIntent on a large flat test ground, so handling
## numbers don't depend on the map's hills and cover. Thresholds are the handling we want
## from car.json, with room for physics variance.

const CAR := "res://modules/car/scenes/box_car.tscn"

var _ground: StaticBody3D
var _car: CarController
var _driver: Node3D


func before_test() -> void:
	_ground = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2000.0, 1.0, 2000.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	_ground.add_child(shape)
	add_child(_ground)
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


func _settle_and_drive() -> void:
	await _frames(60)
	_driver.global_position = _car.global_position
	_car.enter(_driver)


func test_settles_on_its_wheels() -> void:
	await _frames(90)
	assert_float(_car.speed()).is_less(0.2)
	assert_float(_car.global_transform.basis.y.dot(Vector3.UP)).is_greater(0.98)


func test_full_throttle_moves_forward_to_speed() -> void:
	await _settle_and_drive()
	var start := _car.global_position
	_car.intent().throttle = 1.0
	await _frames(180)
	assert_float(_car.forward_speed()).is_greater(10.0)
	# Nose is +Z.
	assert_float(_car.global_position.z).is_greater(start.z + 10.0)


func test_reverse_moves_backwards() -> void:
	await _settle_and_drive()
	_car.intent().throttle = -1.0
	await _frames(90)
	assert_float(_car.forward_speed()).is_less(-1.0)


func test_top_speed_is_respected() -> void:
	await _settle_and_drive()
	_car.intent().throttle = 1.0
	await _frames(480)
	var top: float = _car.config["top_speed"]
	assert_float(_car.forward_speed()).is_less(top + 2.0)
	assert_float(_car.forward_speed()).is_greater(top - 4.0)


func test_steering_right_turns_right() -> void:
	await _settle_and_drive()
	_car.intent().throttle = 0.6
	_car.intent().steer = 1.0
	await _frames(120)
	# Facing +Z, the car's right is -X.
	assert_float(_car.global_position.x).is_less(-1.0)


func test_brakes_to_a_stop() -> void:
	await _settle_and_drive()
	_car.intent().throttle = 1.0
	await _frames(150)
	var braking_from := _car.global_position
	_car.intent().throttle = 0.0
	_car.intent().brake = true
	await _frames(240)
	assert_float(_car.speed()).is_less(0.5)
	assert_float(_car.global_position.distance_to(braking_from)).is_less(30.0)


func test_without_a_driver_the_car_ignores_throttle() -> void:
	await _frames(60)
	_car.intent().throttle = 1.0
	await _frames(120)
	assert_float(_car.speed()).is_less(0.5)


func test_full_lock_at_speed_does_not_roll_it() -> void:
	await _settle_and_drive()
	_car.intent().throttle = 1.0
	await _frames(360)
	_car.intent().steer = 1.0
	await _frames(180)
	assert_float(_car.global_transform.basis.y.y).is_greater(0.8)


func test_a_car_on_its_roof_rights_itself() -> void:
	await _frames(30)
	_car.global_transform = Transform3D(Basis(Vector3.BACK, PI), Vector3(0.0, 2.0, 0.0))
	await _frames(int((float(_car.config["flip_seconds"]) + 1.5) * 60.0))
	await _frames(60)
	assert_float(_car.global_transform.basis.y.y).is_greater(0.9)
