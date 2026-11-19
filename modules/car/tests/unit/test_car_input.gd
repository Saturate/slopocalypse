extends GdUnitTestSuite
## Keys held while a screen is open (typing a bug report) neither drive the car nor get you
## out; with no screen open they drive as before.

const ACTIONS: Array[StringName] = [&"car_throttle", &"car_reverse", &"car_left", &"car_right", &"car_brake", &"car_exit"]

var _input: CarInput
var _screen := RefCounted.new()


func before_test() -> void:
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	_input = auto_free(CarInput.new())
	_input.intent = auto_free(CarIntent.new())
	add_child(_input)


func after_test() -> void:
	for action in ACTIONS:
		Input.action_release(action)
	UiStack.pop(_screen)


func test_held_keys_drive_with_no_screen_open() -> void:
	Input.action_press(&"car_throttle")
	# `physics_frame` fires before nodes step, so the first one is too early.
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_float(_input.intent.throttle).is_greater(0.5)


func test_held_keys_do_nothing_while_a_screen_is_open() -> void:
	UiStack.push(_screen)
	Input.action_press(&"car_throttle")
	Input.action_press(&"car_left")
	Input.action_press(&"car_exit")
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_float(_input.intent.throttle).is_equal(0.0)
	assert_float(_input.intent.steer).is_equal(0.0)
	assert_bool(_input.intent.exit).is_false()
