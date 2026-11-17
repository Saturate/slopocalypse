extends GdUnitTestSuite
## Settings: saved and loaded, kept in range, applied to the engine; a rebind changes the
## InputMap and the key hint, and defaults come back on reset.

const PATH := "user://test_settings.cfg"
const ACTION := "test_settings_action"


func before_test() -> void:
	InputBindings.register({ACTION: ["F"]}, &"test")
	Settings.load_from(PATH)


func after_test() -> void:
	Settings.reset()
	Settings.apply(get_tree().root)
	InputMap.erase_action(ACTION)
	InputBindings.defaults.erase(ACTION)
	UiStack.clear()
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func test_values_survive_a_save_and_load() -> void:
	Settings.set_value("mouse_scale", 1.5)
	Settings.set_value("fov_offset", 10.0)
	Settings.bind(ACTION, KEY_G)
	Settings.save()
	Settings.reset()
	Settings.load_from(PATH)
	assert_float(Settings.mouse_scale()).is_equal(1.5)
	assert_float(Settings.fov_offset()).is_equal(10.0)
	assert_int(Settings.bound_key(ACTION)).is_equal(KEY_G)


func test_values_are_kept_in_range() -> void:
	Settings.set_value("mouse_scale", 50.0)
	Settings.set_value("fov_offset", -90.0)
	assert_float(Settings.mouse_scale()).is_equal(Settings.MOUSE_MAX)
	assert_float(Settings.fov_offset()).is_equal(Settings.FOV_MIN)


func test_apply_sets_ui_scale_and_volume() -> void:
	Settings.set_value("ui_scale", 1.2)
	Settings.set_value("volume", 0.5)
	Settings.apply(get_tree().root)
	assert_float(get_tree().root.content_scale_factor).is_equal_approx(1.2, 0.001)
	assert_float(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Master"))).is_equal_approx(linear_to_db(0.5), 0.01)


func test_a_rebind_changes_the_key_and_reset_brings_the_default_back() -> void:
	Settings.bind(ACTION, KEY_G)
	assert_str(KeyHint.key_for(StringName(ACTION))).is_equal("G")
	Settings.reset()
	assert_str(KeyHint.key_for(StringName(ACTION))).is_equal("F")


func test_a_saved_key_wins_over_the_module_default() -> void:
	InputMap.erase_action(ACTION)
	Settings.bind(ACTION, KEY_K)
	InputBindings.register({ACTION: ["F"]}, &"test")
	assert_str(KeyHint.key_for(StringName(ACTION))).is_equal("K")


func test_the_screen_binds_the_next_key_and_esc_cancels() -> void:
	var screen: SettingsScreen = auto_free(SettingsScreen.new())
	add_child(screen)
	screen.open()
	screen.listen_for(ACTION)
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	screen._input(esc)
	assert_bool(screen.is_waiting_for_key()).is_false()
	assert_str(KeyHint.key_for(StringName(ACTION))).is_equal("F")
	screen.listen_for(ACTION)
	var h := InputEventKey.new()
	h.physical_keycode = KEY_H
	h.pressed = true
	screen._input(h)
	assert_str(KeyHint.key_for(StringName(ACTION))).is_equal("H")
	assert_bool(screen.visible).is_true()
	screen.close()
	assert_bool(FileAccess.file_exists(PATH)).is_true()
