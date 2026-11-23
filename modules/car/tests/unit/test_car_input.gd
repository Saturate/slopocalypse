extends GdUnitTestSuite
## Keys held while a screen is open (typing a bug report) neither drive the car nor get you
## out, and the server is told to let go; with no screen open they drive as before.

const ACTIONS: Array[StringName] = [&"car_throttle", &"car_reverse", &"car_left", &"car_right", &"car_brake", &"car_exit"]


## Records what would go to the server instead of sending it.
class RecordingInput:
	extends CarInput
	var sent: Array[Vector3] = []

	func _send_drive() -> void:
		sent.append(Vector3(intent.throttle, intent.steer, 1.0 if intent.brake else 0.0))


var _input: RecordingInput
var _screen := RefCounted.new()


func before_test() -> void:
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	_input = auto_free(RecordingInput.new())
	_input.intent = auto_free(CarIntent.new())
	add_child(_input)


func after_test() -> void:
	for action in ACTIONS:
		Input.action_release(action)
	UiStack.pop(_screen)


## `physics_frame` fires before nodes step, so the first one is too early.
func _ticks(n: int) -> void:
	for i in n + 1:
		await get_tree().physics_frame


func test_held_keys_drive_with_no_screen_open() -> void:
	Input.action_press(&"car_throttle")
	await _ticks(1)
	assert_float(_input.intent.throttle).is_greater(0.5)
	assert_float(_input.sent[-1].x).is_greater(0.5)


func test_held_keys_do_nothing_while_a_screen_is_open_and_the_server_is_told_to_let_go() -> void:
	Input.action_press(&"car_throttle")
	await _ticks(1)
	UiStack.push(_screen)
	Input.action_press(&"car_left")
	Input.action_press(&"car_exit")
	await _ticks(2)
	assert_float(_input.intent.throttle).is_equal(0.0)
	assert_float(_input.intent.steer).is_equal(0.0)
	assert_bool(_input.intent.exit).is_false()
	assert_vector(_input.sent[-1]).is_equal(Vector3.ZERO)
