extends GdUnitTestSuite
## Walking into a step no higher than `step_height` carries the player up onto it (stairs,
## kerbs, door sills); anything taller stops them, as a wall does.

const PLAYER := "res://modules/player/scenes/player.tscn"

var _player: PlayerController


func _box(at: Vector3, size: Vector3) -> void:
	var body: StaticBody3D = auto_free(StaticBody3D.new())
	body.collision_layer = PhysicsLayers.SOLID
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	body.global_position = at


func before_test() -> void:
	_box(Vector3(0, -0.5, 0), Vector3(40, 1, 40))
	_player = (load(PLAYER) as PackedScene).instantiate()
	add_child(_player)
	# Facing +x.
	_player.rotation.y = -PI / 2.0
	_player.global_position = Vector3(0, 0.05, 0)


func after_test() -> void:
	_player.free()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func test_it_walks_up_a_flight_of_stairs() -> void:
	# Eight steps of 0.175 m, 0.28 m deep, then a landing.
	for k in 8:
		_box(Vector3(3.0 + k * 0.28 + 0.14, (k + 1) * 0.175 / 2.0, 0), Vector3(0.28, (k + 1) * 0.175, 2.0))
	_box(Vector3(3.0 + 8 * 0.28 + 6.0, 1.4 / 2.0, 0), Vector3(12.0, 1.4, 2.0))
	await _frames(10)
	_player.intent().move = Vector2(0, 1)
	await _frames(150)
	assert_float(_player.global_position.y).is_greater(1.3)
	assert_float(_player.global_position.x).is_greater(3.0 + 8 * 0.28)


func test_a_ledge_taller_than_a_step_stops_it() -> void:
	_box(Vector3(3.5, 0.3, 0), Vector3(1.0, 0.6, 2.0))
	await _frames(10)
	_player.intent().move = Vector2(0, 1)
	await _frames(90)
	assert_float(_player.global_position.y).is_less(0.2)
	assert_float(_player.global_position.x).is_less(3.0)
