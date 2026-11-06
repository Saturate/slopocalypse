extends GdUnitTestSuite

const FIX := "res://tests/fixtures/features/"

var _features: FeatureFlags


func before_test() -> void:
	_features = auto_free(FeatureFlags.new())
	Log.begin_capture()


func after_test() -> void:
	Log.end_capture()


func test_reads_flags_from_file() -> void:
	_features.reload(PackedStringArray(), FIX + "flags.json")
	assert_bool(_features.is_enabled(&"car")).is_true()
	assert_bool(_features.is_enabled(&"weapons")).is_false()


func test_command_line_overrides_file() -> void:
	_features.reload(PackedStringArray(["--flags=car:off,weapons:on"]), FIX + "flags.json")
	assert_bool(_features.is_enabled(&"car")).is_false()
	assert_bool(_features.is_enabled(&"weapons")).is_true()


func test_all_optional_off_switches_every_flag_off() -> void:
	_features.reload(PackedStringArray(["--all-optional-off"]), FIX + "flags.json")
	assert_bool(_features.is_enabled(&"car")).is_false()


func test_unknown_flag_is_off_with_a_warning() -> void:
	_features.reload(PackedStringArray(), FIX + "flags.json")
	assert_bool(_features.is_enabled(&"jetpack")).is_false()
	assert_str(LogCapture.text(Log.end_capture())).contains("jetpack")


func test_non_boolean_flag_is_an_error() -> void:
	_features.reload(PackedStringArray(), FIX + "bad_value.json")
	assert_bool(_features.is_enabled(&"car")).is_false()
	assert_str(LogCapture.text(Log.end_capture())).contains("bad_value.json").contains("'car'")


func test_malformed_override_is_an_error() -> void:
	_features.reload(PackedStringArray(["--flags=car"]), FIX + "flags.json")
	assert_str(LogCapture.text(Log.end_capture())).contains("--flags")
