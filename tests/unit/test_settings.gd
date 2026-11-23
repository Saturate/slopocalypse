extends GdUnitTestSuite
## Settings: saved and loaded, kept in range, applied to the engine; a rebind changes the
## InputMap and the key hint, and defaults come back on reset.

const PATH := "user://test_settings.cfg"
const ACTION := "test_settings_action"


func before_test() -> void:
	InputBindings.register({ACTION: ["F"]}, &"test")
	Settings.load_from(PATH)


func after_test() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	Settings.forget_modules()
	# Defaults from an empty file, the real modules' registrations back, and no fixture value
	# left anywhere a later save could write it.
	Settings.reset()
	Settings.load_from(PATH)
	Settings.apply(get_tree().root)
	InputMap.erase_action(ACTION)
	InputBindings.defaults.erase(ACTION)
	UiStack.clear()


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


## Two settings registered by fixture modules, so these tests hold whichever modules are
## present: one always on, one behind a flag that is off.
func _fixture_modules(with_off := false) -> void:
	var on := ModuleLoader.ModuleInfo.new()
	on.id = &"test_lamp"
	on.settings.assign([
		{"key": "test_lamp", "type": "bool", "default": true, "label": "Test lamp", "order": 20.0},
		{"key": "test_glow", "type": "bool", "default": false, "label": "Test glow", "order": 10.0},
	])
	var off := ModuleLoader.ModuleInfo.new()
	off.id = &"test_off"
	off.flag = &"test_settings_flag_off"
	off.settings.assign([{"key": "test_off", "type": "bool", "default": true, "label": "Test off", "order": 5.0}])
	var modules: Array[ModuleLoader.ModuleInfo] = [on]
	if with_off:
		modules.append(off)
	Settings.use_modules(modules)


func test_a_registered_setting_is_on_the_screen_and_saved() -> void:
	_fixture_modules()
	assert_bool(bool(Settings.value("test_lamp"))).is_true()
	assert_bool(bool(Settings.value("test_glow"))).is_false()
	var screen: SettingsScreen = auto_free(SettingsScreen.new())
	add_child(screen)
	screen.open()
	var toggle := screen.find_child("Test lamp", true, false) as Button
	assert_object(toggle).is_not_null()
	assert_bool(toggle.button_pressed).is_true()
	# Rows follow `order`.
	var glow := screen.find_child("Test glow", true, false) as Button
	assert_int(glow.get_index()).is_less(toggle.get_index())
	var heard: Array[Dictionary] = []
	var listen := func(p: Dictionary) -> void: heard.append(p)
	EventBus.subscribe(&"settings.changed", listen)
	toggle.button_pressed = false
	EventBus.unsubscribe(&"settings.changed", listen)
	assert_bool(bool(Settings.value("test_lamp"))).is_false()
	assert_array(heard).is_equal([{"key": "test_lamp", "value": false}])
	screen.close()
	Settings.reset()
	Settings.load_from(PATH)
	assert_bool(bool(Settings.value("test_lamp"))).is_false()


func test_a_module_that_is_off_gets_no_row() -> void:
	# The fixture's flag is unknown to Features, which warns.
	Log.begin_capture()
	_fixture_modules(true)
	var screen: SettingsScreen = auto_free(SettingsScreen.new())
	add_child(screen)
	Log.end_capture()
	assert_object(screen.find_child("Test off", true, false)).is_null()
	assert_object(screen.find_child("Test lamp", true, false)).is_not_null()


func test_a_value_nothing_registers_is_kept_in_the_file() -> void:
	var file := ConfigFile.new()
	file.set_value("game", "gone_module_thing", false)
	file.set_value("game", "volume", 0.5)
	file.save(PATH)
	Settings.load_from(PATH)
	assert_float(float(Settings.value("volume"))).is_equal(0.5)
	Settings.set_value("mouse_scale", 2.0)
	Settings.reset()
	Settings.save()
	var back := ConfigFile.new()
	back.load(PATH)
	assert_bool(back.has_section_key("game", "gone_module_thing")).is_true()
	assert_bool(bool(back.get_value("game", "gone_module_thing"))).is_false()
	# When its module comes back, the player's choice is there.
	var m := ModuleLoader.ModuleInfo.new()
	m.id = &"gone_module"
	m.settings.assign([{"key": "gone_module_thing", "type": "bool", "default": true, "label": "Back", "order": 1.0}])
	Settings.use_modules([m])
	Settings.load_from(PATH)
	assert_bool(bool(Settings.value("gone_module_thing"))).is_false()


func test_a_key_core_or_another_module_owns_is_refused() -> void:
	var a := ModuleLoader.ModuleInfo.new()
	a.id = &"a"
	a.settings.assign([{"key": "fullscreen", "type": "bool", "default": true, "label": "Mine", "order": 1.0}, {"key": "test_twice", "type": "bool", "default": true, "label": "A", "order": 1.0}])
	var b := ModuleLoader.ModuleInfo.new()
	b.id = &"b"
	b.settings.assign([{"key": "test_twice", "type": "bool", "default": false, "label": "B", "order": 1.0}])
	Log.begin_capture()
	Settings.use_modules([a, b])
	var text := LogCapture.text(Log.end_capture())
	assert_str(text).contains("'fullscreen'").contains("core")
	assert_str(text).contains("'test_twice'").contains("module 'b'")
	assert_bool(bool(Settings.value("test_twice"))).is_true()
	assert_bool(bool(Settings.value("fullscreen"))).is_false()


func test_a_wrong_type_in_the_file_falls_back_to_the_default() -> void:
	_fixture_modules()
	var file := ConfigFile.new()
	file.set_value("game", "test_lamp", "yes")
	file.save(PATH)
	Settings.load_from(PATH)
	assert_bool(bool(Settings.value("test_lamp"))).is_true()


func test_a_change_is_announced_once_and_an_unchanged_value_not_at_all() -> void:
	var heard: Array[Dictionary] = []
	var listen := func(p: Dictionary) -> void: heard.append(p)
	EventBus.subscribe(&"settings.changed", listen)
	Settings.set_value("fullscreen", false)
	Settings.set_value("volume", 0.5)
	Settings.set_value("volume", 0.5)
	Settings.reset()
	EventBus.unsubscribe(&"settings.changed", listen)
	assert_array(heard).is_equal([{"key": "volume", "value": 0.5}, {"key": "volume", "value": 1.0}])
