extends GdUnitTestSuite
## A car spawned before the ground under it exists must wait instead of falling through.
## Voxel collision arrives per block, so the car's block can lag the spawn point's.

const MODULE := "res://modules/car/car_module.gd"

var _module: Node


func before_test() -> void:
	_module = (load(MODULE) as GDScript).new()
	add_child(_module)


func after_test() -> void:
	_module.free()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func test_car_waits_for_ground_then_settles_on_it() -> void:
	EventBus.publish(&"world.ready", {"spawn": Vector3(0, 1, 0), "kill_y": -40.0})
	var car: CarController = _module.cars()[0]
	var start := car.global_position
	await _frames(60)
	# No ground yet: the car must not have fallen.
	assert_bool(car.freeze).is_true()
	assert_float(car.global_position.y).is_equal_approx(start.y, 0.01)
	# Ground arrives late, as voxel collision does.
	var floor_body: StaticBody3D = auto_free(StaticBody3D.new())
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	shape.shape = box
	floor_body.add_child(shape)
	add_child(floor_body)
	floor_body.global_position = Vector3(0, -0.5, 0)
	await _frames(90)
	assert_bool(car.freeze).is_false()
	assert_float(car.global_position.y).is_between(0.0, 1.5)
