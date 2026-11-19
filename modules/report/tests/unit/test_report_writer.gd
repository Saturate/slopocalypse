extends GdUnitTestSuite
## A report is one zip: report.json first, then each file given, readable back as written.
## Logs are cut to their newest part, and the name sorts by time.

const DIR := "user://test_reports"


func after_test() -> void:
	for name in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + "/" + name)


func test_the_zip_holds_the_report_and_every_file() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := DIR + "/r.zip"
	var report := {"kind": "bug", "description": "slideshow in the house"}
	var files := {"logs/godot.log": "hello".to_utf8_buffer(), "screenshot.png": PackedByteArray([1, 2, 3])}
	assert_int(ReportWriter.write(path, report, files)).is_equal(OK)
	var zip := ZIPReader.new()
	assert_int(zip.open(path)).is_equal(OK)
	# Folders show up as entries of their own.
	var names := Array(zip.get_files()).filter(func(n: String) -> bool: return not n.ends_with("/"))
	assert_array(names).contains_exactly_in_any_order(["report.json", "logs/godot.log", "screenshot.png"])
	var back: Variant = JSON.parse_string(zip.read_file("report.json").get_string_from_utf8())
	assert_str(str((back as Dictionary)["description"])).is_equal("slideshow in the house")
	assert_str(zip.read_file("logs/godot.log").get_string_from_utf8()).is_equal("hello")
	zip.close()


func test_a_long_log_keeps_its_newest_part() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := DIR + "/long.log"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("old line\n".repeat(100) + "newest line\n")
	f.close()
	var tail := ReportWriter.tail_of(path, 40)
	assert_int(tail.size()).is_less_equal(40)
	assert_str(tail.get_string_from_utf8()).ends_with("newest line\n")
	assert_int(ReportWriter.tail_of(DIR + "/missing.log", 40).size()).is_equal(0)


func test_names_sort_by_time() -> void:
	var a := ReportWriter.file_name({"year": 2026, "month": 11, "day": 9, "hour": 8, "minute": 5, "second": 3})
	var b := ReportWriter.file_name({"year": 2026, "month": 11, "day": 19, "hour": 8, "minute": 5, "second": 3})
	assert_str(a).is_equal("slopocalypse-report-20261109-080503.zip")
	assert_bool(a < b).is_true()


func test_system_info_names_the_machine() -> void:
	var info := ReportWriter.system_info()
	for key in ["os", "cpu", "cpu_cores", "gpu", "renderer", "version"]:
		assert_bool(info.has(key)).override_failure_message(key).is_true()
