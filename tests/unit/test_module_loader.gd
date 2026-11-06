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
