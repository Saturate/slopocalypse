extends GdUnitTestSuite
## A saved report is one zip holding report.json (kind, description, machine, settings, game)
## and this run's log, plus the screenshot when there is one; extra fields land in report.json.

const MODULE := "res://modules/report/report_module.gd"
const DIR := "user://test_report_module"

var _module: Node


func before_test() -> void:
	_module = auto_free((load(MODULE) as GDScript).new())
	_module.set(&"folder", DIR)
	add_child(_module)


func after_test() -> void:
	for name in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + "/" + name)


func _read(path: String) -> Dictionary:
	var zip := ZIPReader.new()
	assert_int(zip.open(path)).is_equal(OK)
	var out := {}
	for name in zip.get_files():
		out[name] = zip.read_file(name)
	zip.close()
	return out


func test_a_bug_report_holds_what_happened_the_machine_and_the_log() -> void:
	var path: String = _module.call(&"save_report", "bug", "slideshow in the house", PackedByteArray([137, 80, 78, 71]))
	assert_str(path).is_not_empty()
	var files := _read(path)
	assert_bool(files.has("screenshot.png")).is_true()
	assert_bool(files.has("logs/game.log")).is_true()
	var report: Dictionary = JSON.parse_string((files["report.json"] as PackedByteArray).get_string_from_utf8())
	assert_str(str(report["kind"])).is_equal("bug")
	assert_str(str(report["description"])).is_equal("slideshow in the house")
	assert_bool((report["system"] as Dictionary).has("gpu")).is_true()
	assert_bool((report["settings"] as Dictionary).has("fov_offset")).is_true()
	assert_bool((report["game"] as Dictionary).has("mode")).is_true()


func test_extra_fields_go_into_report_json_and_no_screenshot_is_fine() -> void:
	var path: String = _module.call(&"save_report", "benchmark", "", PackedByteArray(), {"benchmark": {"fps_mean": 61.5}})
	var files := _read(path)
	assert_bool(files.has("screenshot.png")).is_false()
	var report: Dictionary = JSON.parse_string((files["report.json"] as PackedByteArray).get_string_from_utf8())
	assert_float(float((report["benchmark"] as Dictionary)["fps_mean"])).is_equal(61.5)


func test_addresses_and_names_from_the_command_line_stay_out() -> void:
	var game: Dictionary = (_module.call(&"gather", "bug", "") as Dictionary)["game"]
	for arg: String in game["args"]:
		assert_bool(arg.begins_with("--connect=") or arg.begins_with("--name=")).is_false()
