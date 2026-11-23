extends GdUnitTestSuite
## UiStack: the screen opened last is on top, the mouse is free while anything is open and
## goes back to the game only when the last screen closes and a player is playing.


func after_test() -> void:
	UiStack.clear()


func test_last_opened_is_on_top() -> void:
	var a := RefCounted.new()
	var b := RefCounted.new()
	UiStack.push(a)
	UiStack.push(b)
	assert_bool(UiStack.is_top(b)).is_true()
	assert_bool(UiStack.is_top(a)).is_false()
	UiStack.pop(b)
	assert_bool(UiStack.is_top(a)).is_true()


func test_pushing_an_open_screen_moves_it_to_the_top() -> void:
	var a := RefCounted.new()
	var b := RefCounted.new()
	UiStack.push(a)
	UiStack.push(b)
	UiStack.push(a)
	assert_int(UiStack.count()).is_equal(2)
	assert_bool(UiStack.is_top(a)).is_true()


func test_mouse_is_free_while_a_screen_is_open_and_captured_after() -> void:
	UiStack.set_captures_when_empty(true)
	assert_int(UiStack.mouse_mode()).is_equal(Input.MOUSE_MODE_CAPTURED)
	var a := RefCounted.new()
	var b := RefCounted.new()
	UiStack.push(a)
	UiStack.push(b)
	UiStack.pop(b)
	assert_int(UiStack.mouse_mode()).is_equal(Input.MOUSE_MODE_VISIBLE)
	UiStack.pop(a)
	assert_int(UiStack.mouse_mode()).is_equal(Input.MOUSE_MODE_CAPTURED)


func test_without_a_player_the_mouse_stays_free() -> void:
	UiStack.push(RefCounted.new())
	UiStack.clear()
	assert_int(UiStack.mouse_mode()).is_equal(Input.MOUSE_MODE_VISIBLE)


func test_a_freed_screen_does_not_block() -> void:
	var node := Node.new()
	UiStack.push(node)
	node.free()
	assert_bool(UiStack.is_blocking()).is_false()


func test_cancel_is_ui_cancel_pressed() -> void:
	var press := InputEventAction.new()
	press.action = &"ui_cancel"
	press.pressed = true
	assert_bool(UiStack.is_cancel(press)).is_true()
	var release := InputEventAction.new()
	release.action = &"ui_cancel"
	assert_bool(UiStack.is_cancel(release)).is_false()
