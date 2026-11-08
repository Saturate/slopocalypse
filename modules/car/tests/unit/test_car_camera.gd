extends GdUnitTestSuite
## The chase camera sits behind and above the car, catches up smoothly when the car jumps
## ahead, swings round with the mouse, and pulls in in front of a wall.

const CAR := "res://modules/car/scenes/box_car.tscn"

var _car: CarController
var _camera: Camera3D


func before_test() -> void:
	_car = auto_free((load(CAR) as PackedScene).instantiate())
	add_child(_car)
	_car.freeze = true
	_camera = _car.camera()
	_camera.current = true


func test_starts_behind_and_above_the_car() -> void:
	_camera.call(&"place", 1.0 / 60.0)
	var local := _car.to_local(_camera.global_position)
	# Behind is -Z: the car's nose is +Z.
	assert_float(local.z).is_less(-4.0)
	assert_float(local.y).is_greater(1.0)


func test_catches_up_smoothly() -> void:
	_camera.call(&"place", 1.0 / 60.0)
	_car.global_position += Vector3(0.0, 0.0, 10.0)
	var before := _camera.global_position
	_camera.call(&"place", 1.0 / 60.0)
	var moved := _camera.global_position.distance_to(before)
	assert_float(moved).is_greater(0.1)
	assert_float(moved).is_less(5.0)
	for i in 240:
		_camera.call(&"place", 1.0 / 60.0)
	assert_float(_car.to_local(_camera.global_position).z).is_less(-4.0)


func test_mouse_swings_it_round() -> void:
	_camera.call(&"orbit", PI / 2.0)
	# Less than the time it waits before drifting back behind.
	for i in 50:
		_camera.call(&"place", 1.0 / 60.0)
	var local := _car.to_local(_camera.global_position)
	assert_float(absf(local.x)).is_greater(absf(local.z))


func test_pulls_in_in_front_of_a_wall() -> void:
	await get_tree().physics_frame
	var wall: StaticBody3D = auto_free(StaticBody3D.new())
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10.0, 10.0, 0.5)
	shape.shape = box
	wall.add_child(shape)
	add_child(wall)
	wall.global_position = _car.to_global(Vector3(0.0, 1.0, -3.0))
	# A new body is only in the physics space after a step.
	await get_tree().physics_frame
	await get_tree().physics_frame
	_camera.call(&"place", 1.0 / 60.0)
	assert_float(_car.to_local(_camera.global_position).z).is_greater(-3.0)
