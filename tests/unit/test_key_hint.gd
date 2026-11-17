extends GdUnitTestSuite
## Key hints read the bound key from the InputMap, so they follow a rebind; the prompt
## stack keeps one line per id, in order, and hides while a screen is open.

const ACTION := &"test_hint_action"


func before_test() -> void:
	InputMap.add_action(ACTION)
	_bind(KEY_F)


func after_test() -> void:
	InputMap.erase_action(ACTION)
	UiStack.clear()


func _bind(key: Key) -> void:
	InputMap.action_erase_events(ACTION)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(ACTION, ev)


func test_key_for_names_the_bound_key() -> void:
	assert_str(KeyHint.key_for(ACTION)).is_equal("F")


func test_hint_shows_the_new_key_after_a_rebind() -> void:
	var hint: KeyHint = auto_free(KeyHint.new(ACTION, "Trade"))
	_bind(KEY_G)
	hint.refresh()
	assert_str(KeyHint.key_for(ACTION)).is_equal("G")
	assert_str((hint.get_child(0) as Label).text).is_equal("G")
	assert_str((hint.get_child(1) as Label).text).is_equal("Trade")


func test_mouse_buttons_and_missing_actions() -> void:
	InputMap.action_erase_events(ACTION)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	InputMap.action_add_event(ACTION, click)
	assert_str(KeyHint.key_for(ACTION)).is_equal("RMB")
	assert_str(KeyHint.key_for(&"no_such_action")).is_equal("?")
	assert_str(KeyHint.key_for(&"ui_cancel")).is_equal("Esc")


func test_a_hint_without_an_action_is_text_only() -> void:
	var hint: KeyHint = auto_free(KeyHint.new(&"", "Choose a mission first"))
	assert_bool((hint.get_child(0) as Label).visible).is_false()


func test_prompt_lines_stack_in_order_and_update_in_place() -> void:
	var stack: PromptStack = auto_free(PromptStack.new())
	add_child(stack)
	stack.set_line(&"b", ACTION, "Second", 2)
	stack.set_line(&"a", ACTION, "First", 1)
	stack.set_line(&"b", ACTION, "Second, changed", 2)
	var column := stack.get_child(0) as VBoxContainer
	assert_int(column.get_child_count()).is_equal(2)
	assert_str((column.get_child(0) as KeyHint).text).is_equal("First")
	assert_str(stack.line_text(&"b")).is_equal("Second, changed")
	stack.clear_line(&"a")
	assert_bool(stack.has_line(&"a")).is_false()


func test_prompts_hide_while_a_screen_is_open() -> void:
	var stack: PromptStack = auto_free(PromptStack.new())
	add_child(stack)
	stack.set_line(&"a", ACTION, "First")
	UiStack.push(stack)
	stack._process(0.0)
	assert_bool((stack.get_child(0) as Control).visible).is_false()
	UiStack.pop(stack)
	stack._process(0.0)
	assert_bool((stack.get_child(0) as Control).visible).is_true()


func test_of_returns_one_stack_per_scene() -> void:
	var first := PromptStack.of(get_tree())
	var second := PromptStack.of(get_tree())
	assert_object(second).is_same(first)
	await get_tree().process_frame
	assert_bool(first.is_inside_tree()).is_true()
	first.free()
