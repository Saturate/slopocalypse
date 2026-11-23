extends GdUnitTestSuite
## Ladders (`Ladders`): heading into one climbs it, heading away climbs down, neither holds on;
## it never lifts anyone past its top. Walking past it, a player or a soldier (the same body,
## driven by a brain) stays on the ground, and so does someone on the deck it leads to.

const PLAYER := "res://modules/player/scenes/player.tscn"
## A ladder against a wall in front of the player (-z): climbed facing -z, 6 m tall.
const LADDER_TOP := 6.0

var _player: PlayerController
var _owner := RefCounted.new()


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
	_box(Vector3(0, LADDER_TOP / 2.0, -0.6), Vector3(2.0, LADDER_TOP, 0.2))
	Ladders.add(_owner, Transform3D(Basis.IDENTITY, Vector3(0, LADDER_TOP / 2.0, -0.1)), Vector3(0.4, LADDER_TOP / 2.0, 0.4), Vector3.FORWARD)
	_player = (load(PLAYER) as PackedScene).instantiate()
	add_child(_player)
	_player.global_position = Vector3(0, 0.05, 0)


func after_test() -> void:
	Ladders.remove(_owner)
	_player.free()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func test_heading_into_it_climbs_up_and_stops_at_the_top() -> void:
	_player.intent().move = Vector2(0, 1)
	await _frames(60)
	var speed := float(_player.config["climb_speed"])
	assert_float(_player.global_position.y).is_greater(speed * 0.7)
	await _frames(240)
	# Held at the top of the ladder, never above it.
	assert_float(_player.global_position.y).is_less_equal(LADDER_TOP + 0.05)


func test_letting_go_holds_on_and_heading_away_climbs_down() -> void:
	_player.intent().move = Vector2(0, 1)
	await _frames(60)
	_player.intent().move = Vector2.ZERO
	var held := _player.global_position.y
	await _frames(30)
	assert_float(_player.global_position.y).is_equal_approx(held, 0.05)
	_player.intent().move = Vector2(0, -1)
	await _frames(30)
	assert_float(_player.global_position.y).is_less(held - 0.5)
	# Still on the ladder, not pulled off it.
	assert_float(_player.global_position.z).is_greater(-0.6)
	assert_float(_player.global_position.z).is_less(0.6)


func test_walking_sideways_past_it_does_not_climb() -> void:
	_player.global_position = Vector3(-3, 0.05, 0)
	_player.intent().move = Vector2(1, 0)
	await _frames(90)
	assert_float(_player.global_position.x).is_greater(1.0)
	assert_float(_player.global_position.y).is_less(0.2)


func test_a_soldier_walking_past_does_not_climb() -> void:
	# A brain turns the body the way it walks: here along the wall, across the ladder's foot.
	_player.global_position = Vector3(-3, 0.05, 0)
	_player.rotation.y = -PI / 2.0
	_player.intent().move = Vector2(0, 1)
	await _frames(90)
	assert_float(_player.global_position.x).is_greater(1.0)
	assert_float(_player.global_position.y).is_less(0.2)


func test_off_the_ladder_the_player_falls() -> void:
	_player.global_position = Vector3(5, 3, 0)
	await _frames(30)
	assert_float(_player.global_position.y).is_less(1.0)


func test_climbing_is_set_on_it_and_clears_stepping_off_at_the_bottom() -> void:
	assert_bool(_player.climbing).is_false()
	_player.intent().move = Vector2(0, 1)
	await _frames(40)
	assert_bool(_player.climbing).is_true()
	_player.intent().move = Vector2(0, -1)
	await _frames(90)
	# Back on the ground and walked back off it.
	assert_float(_player.global_position.y).is_less(0.2)
	assert_bool(_player.climbing).is_false()


func test_climbing_clears_stepping_off_at_the_top() -> void:
	# A deck behind the wall at the ladder's top, to step onto.
	_box(Vector3(0, LADDER_TOP - 0.25, -2.1), Vector3(4.0, 0.5, 2.8))
	_player.intent().move = Vector2(0, 1)
	var climbed := false
	for i in 300:
		await get_tree().physics_frame
		climbed = climbed or _player.climbing
		if _player.global_position.z < -1.2:
			break
	_player.intent().move = Vector2.ZERO
	await _frames(10)
	assert_bool(climbed).is_true()
	assert_bool(_player.climbing).is_false()
	assert_float(_player.global_position.y).is_equal_approx(LADDER_TOP, 0.1)
	assert_float(_player.global_position.z).is_less(-1.0)


func test_put_down_in_mid_air_in_reach_falls_instead_of_hanging() -> void:
	# Spawned or moved there: nobody heading anywhere, so nothing to grab with.
	_player.global_position = Vector3(0, 3, 0)
	var held := false
	for i in 60:
		await get_tree().physics_frame
		held = held or _player.climbing
	assert_bool(held).is_false()
	assert_float(_player.global_position.y).is_less(0.2)


func test_falling_fast_past_it_does_not_grab() -> void:
	_player.global_position = Vector3(0, 5, 0)
	_player.velocity = Vector3(0, -float(_player.config["climb_grab_fall_speed"]) - 2.0, 0)
	_player.intent().move = Vector2(0, 1)
	var held := false
	for i in 300:
		await get_tree().physics_frame
		if _player.is_on_floor():
			break
		held = held or _player.climbing
	assert_bool(held).is_false()
	assert_float(_player.global_position.y).is_less(0.2)


func test_dropping_slowly_onto_it_heading_in_grabs() -> void:
	_player.global_position = Vector3(0, 3, 0)
	_player.intent().move = Vector2(0, 1)
	await _frames(5)
	assert_bool(_player.climbing).is_true()
	_player.intent().move = Vector2.ZERO
	await _frames(30)
	assert_float(_player.global_position.y).is_greater(2.5)


func test_backing_off_the_deck_at_the_top_climbs_down() -> void:
	_box(Vector3(0, LADDER_TOP - 0.25, -2.1), Vector3(4.0, 0.5, 2.8))
	_player.global_position = Vector3(0, LADDER_TOP + 0.05, -1.4)
	# Facing the deck, back to the drop: backing off heads away from the ladder's way in.
	_player.intent().move = Vector2(0, -1)
	var held := false
	for i in 120:
		await get_tree().physics_frame
		held = held or _player.climbing
	assert_bool(held).is_true()
	assert_float(_player.global_position.y).is_less(LADDER_TOP - 1.0)
	# Down the ladder, not dropped beside it.
	assert_float(_player.global_position.z).is_less(0.8)


func test_climbing_lets_go_of_the_trigger_and_the_sights() -> void:
	_player.intent().move = Vector2(0, 1)
	await _frames(30)
	assert_bool(_player.climbing).is_true()
	_player.intent().fire = true
	_player.intent().aim = true
	await _frames(1)
	assert_bool(_player.intent().fire).is_false()
	assert_bool(_player.intent().aim).is_false()


func test_first_person_gun_is_lowered_while_climbing() -> void:
	var animator := PlayerBodyAnimator.new()
	animator.player = _player
	_player.add_child(animator)
	PlayerBody.first_person(_player.get_node("Body"))
	var aim := _player.get_node("Body/Skeleton/Aim")
	await _frames(10)
	assert_float(float(aim.get(&"lowered"))).is_equal_approx(0.0, 0.01)
	_player.intent().move = Vector2(0, 1)
	await _frames(60)
	assert_bool(_player.climbing).is_true()
	assert_float(float(aim.get(&"lowered"))).is_greater(0.9)


func test_jumping_backwards_at_its_foot_does_not_grab() -> void:
	_player.global_position = Vector3(0, 0.05, 0.3)
	await _frames(5)
	_player.intent().move = Vector2(0, -1)
	_player.intent().jump = true
	var held := false
	for i in 20:
		await get_tree().physics_frame
		held = held or _player.climbing
	assert_bool(held).is_false()


func test_put_somewhere_else_lets_go() -> void:
	_player.intent().move = Vector2(0, 1)
	await _frames(40)
	assert_bool(_player.climbing).is_true()
	_player.intent().move = Vector2.ZERO
	# A respawn or back-to-spawn, here into mid-air beside the same ladder.
	_player.put_at(Vector3(0, 3, 0))
	assert_bool(_player.climbing).is_false()
	await _frames(60)
	assert_float(_player.global_position.y).is_less(0.2)
