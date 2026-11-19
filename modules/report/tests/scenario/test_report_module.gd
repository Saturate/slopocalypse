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


func test_the_report_lists_feature_flags() -> void:
	var game: Dictionary = (_module.call(&"gather", "bug", "") as Dictionary)["game"]
	assert_bool((game["flags"] as Dictionary).has("report")).is_true()


func test_a_clean_shot_hides_the_session_overlay_and_brings_it_back() -> void:
	var overlay := auto_free(CanvasLayer.new()) as CanvasLayer
	overlay.add_to_group(&"session_overlay")
	add_child(overlay)
	var screen := ReportScreen.new()
	add_child(auto_free(screen))
	_module.set(&"_screen", screen)
	_module.call(&"open_clean")
	assert_bool(overlay.visible).is_false()
	# A second press while it waits for the clean frame is ignored.
	_module.call(&"open_clean")
	for i in 4:
		await get_tree().process_frame
	assert_bool(overlay.visible).is_true()
	assert_bool(screen.is_open()).is_true()
	screen.close()
