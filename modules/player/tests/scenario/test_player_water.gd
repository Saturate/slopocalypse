extends GdUnitTestSuite
## Walking into water: past `wade_depth` the player slows to `wade_speed`; past `swim_depth`
## they float, move at `swim_speed` and can't fire. A flat floor and a stand-in for the world
## that says how deep the water is: shallow from x 10, deep from x 30, and from x 60 the sea
## past its depth limit, where a swimmer tires and then gets hurt (#454).

const PLAYER := "res://modules/player/scenes/player.tscn"


class FakeWater extends Node:
	func _ready() -> void:
		add_to_group(&"ground")

	func water_level_at(p: Vector3) -> float:
		return 2.0 if p.x > 30.0 else (0.8 if p.x > 10.0 else NAN)

	func water_depth_at(p: Vector3) -> float:
		var level := water_level_at(p)
		return 0.0 if is_nan(level) else level

	func sea_depth_at(p: Vector3) -> float:
		return 9.0 if p.x > 60.0 else 0.0

	func sea_depth_limit() -> float:
		return 6.0


var _player: PlayerController


func before_test() -> void:
	var floor_body: StaticBody3D = auto_free(StaticBody3D.new())
	floor_body.collision_layer = PhysicsLayers.SOLID
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 40)
	shape.shape = box
	shape.position = Vector3(50, -0.5, 0)
	floor_body.add_child(shape)
	add_child(floor_body)
	add_child(auto_free(FakeWater.new()))
	_player = (load(PLAYER) as PackedScene).instantiate()
	add_child(_player)
	# Facing +x, so "forward" walks into the water.
	_player.rotation.y = -PI / 2.0
	_player.global_position = Vector3(0, 0.2, 0)


func after_test() -> void:
	_player.free()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _speed_at(x: float) -> float:
	_player.global_position = Vector3(x, 0.2, 0)
	_player.velocity = Vector3.ZERO
	_player.intent().move = Vector2(0, 1)
	await _frames(30)
	return _player.horizontal_speed()


func test_it_slows_in_shallow_water_and_swims_in_deep() -> void:
	await _frames(20)
	var walk := float(_player.config["walk_speed"])
	assert_float(await _speed_at(0.0)).is_equal_approx(walk, walk * 0.05)
	assert_bool(_player.swimming).is_false()
	var wade := await _speed_at(12.0)
	assert_float(wade).is_equal_approx(walk * float(_player.config["wade_speed"]), walk * 0.05)
	assert_bool(_player.swimming).is_false()
	var swim := await _speed_at(40.0)
	assert_float(swim).is_equal_approx(walk * float(_player.config["swim_speed"]), walk * 0.05)
	assert_bool(_player.swimming).is_true()
	# Afloat: feet `swim_depth` under the surface (2 m), not on the bottom.
	await _frames(60)
	assert_float(_player.global_position.y).is_equal_approx(2.0 - float(_player.config["swim_depth"]), 0.1)
	# The weapon stays out of the water.
	assert_bool(_player.get_meta(&"swimming", false)).is_true()
	# Back on land: walking again.
	assert_float(await _speed_at(0.0)).is_equal_approx(walk, walk * 0.05)
	assert_bool(_player.get_meta(&"swimming", true)).is_false()


func test_swimming_out_past_the_seas_depth_limit_tires_then_hurts_and_coming_back_recovers() -> void:
	_player.config["sea_stamina_seconds"] = 0.5
	_player.config["sea_stamina_recovery"] = 2.0
	_player.config["exhausted_damage"] = 30.0
	var health := _player.get_node("Health") as HealthComponent
	var full := health.health
	# Deep water short of the limit: no drain.
	_player.global_position = Vector3(40, 1.0, 0)
	await _frames(30)
	assert_bool(_player.swimming).is_true()
	assert_bool(_player.far_out()).is_false()
	assert_float(_player.sea_stamina_share()).is_equal(1.0)
	# Out past it: stamina runs out within its seconds, then health goes.
	_player.global_position = Vector3(80, 1.0, 0)
	await _frames(20)
	assert_bool(_player.far_out()).is_true()
	assert_float(_player.sea_stamina_share()).is_less(1.0)
	assert_float(health.health).is_equal(full)
	# Out of it after half a second, then a hurt once a second.
	await _frames(90)
	assert_float(_player.sea_stamina_share()).is_equal(0.0)
	assert_float(health.health).is_less(full)
	# Back in from the deep: it comes back.
	_player.global_position = Vector3(40, 1.0, 0)
	await _frames(30)
	assert_bool(_player.far_out()).is_false()
	assert_float(_player.sea_stamina_share()).is_greater(0.5)
