extends GdUnitTestSuite

# Fixture modules: alpha (no flag, always on), beta depends on alpha, gamma depends on a
# module that does not exist, delta is flagged, epsilon depends on delta.
const ROOT := "res://tests/fixtures/modules"


func before_test() -> void:
	Log.begin_capture()


func after_test() -> void:
	Log.end_capture()


func _ids(mods: Array[ModuleLoader.ModuleInfo]) -> Array[String]:
	var out: Array[String] = []
	for m in mods:
		out.append(String(m.id))
	return out


func test_discovers_every_manifest() -> void:
	var found := _ids(ModuleLoader.discover(ROOT))
	found.sort()
	assert_array(found).is_equal(["alpha", "beta", "delta", "epsilon", "gamma"])


func test_dependencies_load_before_dependents() -> void:
	var order := _ids(ModuleLoader.resolve(ModuleLoader.discover(ROOT), func(_f: StringName) -> bool: return true))
	assert_bool(order.find("alpha") < order.find("beta")).is_true()
	assert_bool(order.find("delta") < order.find("epsilon")).is_true()


func test_missing_dependency_skips_module_with_reason() -> void:
	var order := _ids(ModuleLoader.resolve(ModuleLoader.discover(ROOT), func(_f: StringName) -> bool: return true))
	assert_array(order).not_contains(["gamma"])
	assert_int(Log.end_capture().size()).is_equal(0)


func test_flag_off_skips_module_and_its_dependents() -> void:
	var enabled := func(f: StringName) -> bool: return f != &"delta"
	var order := _ids(ModuleLoader.resolve(ModuleLoader.discover(ROOT), enabled))
	assert_array(order).not_contains(["delta", "epsilon"])
	assert_array(order).contains(["alpha", "beta"])


func test_module_without_flag_is_always_on() -> void:
	var order := _ids(ModuleLoader.resolve(ModuleLoader.discover(ROOT), func(_f: StringName) -> bool: return false))
	assert_array(order).is_equal(["alpha"])


func test_bad_manifest_is_an_error() -> void:
	var info := ModuleLoader.parse_manifest("res://tests/fixtures/modules/alpha", {"id": "alpha"})
	assert_object(info).is_null()
	assert_str(LogCapture.text(Log.end_capture())).contains("module.json").contains("'depends_on'")


func _manifest(extra: Dictionary) -> Dictionary:
	return {"id": "alpha", "depends_on": [], "flag": "", "entry": "module.gd"}.merged(extra)


func test_debug_calls_and_settings_are_read_from_the_manifest() -> void:
	var info := ModuleLoader.parse_manifest(ROOT.path_join("alpha"), _manifest({
		"debug_calls": ["server_poke", "count"],
		"settings": [{"key": "alpha_lamp", "type": "bool", "default": true, "label": "Lamp", "order": 10.0}],
	}))
	assert_array(info.debug_calls).is_equal(["server_poke", "count"])
	assert_int(info.settings.size()).is_equal(1)
	assert_str(str(info.settings[0]["key"])).is_equal("alpha_lamp")
	assert_bool(bool(info.settings[0]["default"])).is_true()
	# Both are optional.
	var plain := ModuleLoader.parse_manifest(ROOT.path_join("alpha"), _manifest({}))
	assert_array(plain.debug_calls).is_empty()
	assert_array(plain.settings).is_empty()


func test_bad_debug_calls_or_settings_are_an_error() -> void:
	var bad: Array[Dictionary] = [
		{"debug_calls": "count"},
		{"debug_calls": ["not a name"]},
		{"debug_calls": ["_ready"]},
		{"debug_calls": ["count", "count"]},
		{"settings": [{"key": "x", "type": "bool", "default": true, "label": "A.b", "order": 1.0}]},
		{"settings": {}},
		{"settings": [{"key": "x", "type": "bool", "default": true, "label": "X"}]},
		{"settings": [{"key": "x", "type": "colour", "default": true, "label": "X", "order": 1.0}]},
		{"settings": [{"key": "x", "type": "bool", "default": 1.0, "label": "X", "order": 1.0}]},
		{"settings": [{"key": "has space", "type": "bool", "default": true, "label": "X", "order": 1.0}]},
	]
	for extra in bad:
		assert_object(ModuleLoader.parse_manifest(ROOT.path_join("alpha"), _manifest(extra))).override_failure_message(str(extra)).is_null()
	var text := LogCapture.text(Log.end_capture())
	assert_str(text).contains("debug_calls").contains("'order'").contains("colour").contains("default").contains("plain name")
