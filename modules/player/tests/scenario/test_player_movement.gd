extends GdUnitTestSuite
## Drives the real player scene on the real world scene through PlayerIntent, stepping
## physics frames. No input events: headless Godot does not deliver them.

const WORLD := "res://modules/world/scenes/world.tscn"
const PLAYER := "res://modules/player/scenes/player.tscn"

var _world: Node3D
var _player: PlayerController


func before_test() -> void:
	_world = (load(WORLD) as PackedScene).instantiate()
	add_child(_world)
	_player = (load(PLAYER) as PackedScene).instantiate()
	add_child(_player)
	_player.global_position = Vector3(0.0, 3.0, 0.0)


func after_test() -> void:
	_player.free()
	_world.free()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func test_lands_and_stays_on_terrain() -> void:
	await _frames(300)
	assert_bool(_player.is_on_floor()).is_true()
	# The spawn area is flat at height 0 and the body origin is at the feet.
	assert_float(_player.global_position.y).is_equal_approx(0.0, 0.1)


func test_walks_forward_at_tuned_speed() -> void:
	await _frames(60)
	var start := _player.global_position
	_player.intent().move = Vector2(0.0, 1.0)
	await _frames(60)
	var walk: float = _player.config["walk_speed"]
	assert_float(_player.horizontal_speed()).is_equal_approx(walk, walk * 0.1)
	# Forward is -Z in Godot.
	assert_float(_player.global_position.z).is_less(start.z - 2.0)


func test_sprint_is_faster_than_walk() -> void:
	await _frames(60)
	_player.intent().move = Vector2(0.0, 1.0)
	_player.intent().sprint = true
	await _frames(60)
	var sprint: float = _player.config["sprint_speed"]
	assert_float(_player.horizontal_speed()).is_equal_approx(sprint, sprint * 0.1)


func test_crouch_lowers_the_head_and_slows_down() -> void:
	await _frames(60)
	var head: Node3D = _player.get_node("Head")
	var standing_eye := head.position.y
	_player.intent().crouch = true
	_player.intent().move = Vector2(0.0, 1.0)
	await _frames(60)
	assert_float(head.position.y).is_less(standing_eye - 0.4)
	var crouch: float = _player.config["crouch_speed"]
	assert_float(_player.horizontal_speed()).is_equal_approx(crouch, crouch * 0.1)


func test_jump_leaves_the_ground_and_comes_back() -> void:
	await _frames(60)
	_player.intent().jump = true
	await _frames(10)
	assert_bool(_player.is_on_floor()).is_false()
	assert_float(_player.global_position.y).is_greater(0.3)
	await _frames(120)
	assert_bool(_player.is_on_floor()).is_true()


func test_aiming_down_sights_slows_down_and_blocks_sprint() -> void:
	await _frames(60)
	_player.intent().move = Vector2(0.0, 1.0)
	_player.intent().sprint = true
	_player.intent().aim = true
	await _frames(90)
	var expected: float = float(_player.config["walk_speed"]) * float(_player.config["ads_speed_multiplier"])
	assert_bool(_player.is_sprinting()).is_false()
	assert_float(_player.horizontal_speed()).is_equal_approx(expected, expected * 0.1)
