extends GdUnitTestSuite
## On a client the controller copy ticks too. When its physics tick lands before the input's
## frame (nearly always at low frame rates), it must not eat the mouse look: the view turns
## by what the mouse moved, whichever runs first.

const PLAYER := "res://modules/player/scenes/player.tscn"

var _player: PlayerController
var _input: PlayerInput


func before_test() -> void:
	_player = auto_free((load(PLAYER) as PackedScene).instantiate())
	add_child(_player)
	_input = PlayerInput.new()
	_input.player = _player
	_input.intent = _player.intent()
	_player.add_child(_input)
	# As on a client: this instance does not simulate the player, the server does.
	_input._remote = true


func after_test() -> void:
	UiStack.clear()


func test_a_physics_tick_before_the_frame_does_not_eat_the_look() -> void:
	# One frame first, so the input has claimed the aim as on a running client.
	_input._process_tick(1.0 / 60.0)
	_player.intent().look_delta = Vector2(0.05, 0.0)
	_player._physics_tick(1.0 / 60.0)
	_input._process_tick(1.0 / 60.0)
	assert_float(_player.rotation.y).is_equal_approx(-0.05, 0.0001)
	# And the next tick keeps it.
	_player._physics_tick(1.0 / 60.0)
	assert_float(_player.rotation.y).is_equal_approx(-0.05, 0.0001)


func test_many_ticks_and_frames_add_up() -> void:
	_input._process_tick(1.0 / 60.0)
	for i in 10:
		_player.intent().look_delta += Vector2(0.01, 0.0)
		_player._physics_tick(1.0 / 60.0)
		_input._process_tick(1.0 / 60.0)
	assert_float(_player.rotation.y).is_equal_approx(-0.1, 0.0001)
