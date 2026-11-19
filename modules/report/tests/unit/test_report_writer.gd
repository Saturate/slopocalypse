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


func test_only_shareable_flags_are_kept() -> void:
	var args := PackedStringArray(["--connect=10.0.0.5:7777", "--name=Allan", "--solo", "--flags=car:off", "--log-file=/Users/someone/x.log", "--bind=0.0.0.0", "--save=/tmp/w.db", "--bench=deaths"])
	assert_array(ReportWriter.public_args(args)).contains_exactly(["--solo", "--flags=car:off", "--bench=deaths"])


func test_logs_lose_home_folders_and_addresses() -> void:
	var log := "[INFO] net: connecting to friend.example.org:7777\n[INFO] perf: logging to /Users/someone/Library/x.ndjson\nFriends join at 192.168.1.20:7777\nbuild 0.8.0"
	var out := ReportWriter.scrub(log, ["/Users/someone"])
	assert_str(out).not_contains("friend.example.org")
	assert_str(out).not_contains("someone")
	assert_str(out).not_contains("192.168.1.20")
	assert_str(out).contains("connecting to <address>:7777")
	assert_str(out).contains("<folder>/Library/x.ndjson")
	assert_str(out).contains("build 0.8.0")


func test_failed_joins_ipv6_windows_paths_and_the_account_name_are_written_over() -> void:
	var log := "WARN net: Could not reach friend.duckdns.org:7777. Is the host running?\nINFO net: connecting to [fe80::1c2b:3d4e]:7777\nINFO data: using C:/Users/Bob/Downloads/game/tweaks/x.json\nhello bob and Bob\nat 10:41:20"
	var out := ReportWriter.scrub(log, ["C:\\Users\\Bob"], "Bob")
	assert_str(out).not_contains("duckdns")
	assert_str(out).not_contains("fe80")
	assert_str(out).not_contains("Bob")
	assert_str(out).contains("<folder>/Downloads")
	assert_str(out).contains("at 10:41:20")


func test_source_locations_survive_while_hosts_go() -> void:
	var log := "   at: _ready (res://core/net.gd:123)\n   at: get_node (scene/main/node.cpp:1877)\nERROR: slop_core::inventory::place failed in Node::get\npanicked at src/lib.rs:88:5\nCould not reach friend.duckdns.org:7777\nconnecting to [fe80::1]:7777 and ::1"
	var out := ReportWriter.scrub(log, [])
	for kept in ["res://core/net.gd:123", "scene/main/node.cpp:1877", "slop_core::inventory::place", "Node::get", "src/lib.rs:88:5"]:
		assert_str(out).override_failure_message(kept + " in: " + out).contains(kept)
	assert_str(out).not_contains("duckdns")
	assert_str(out).not_contains("fe80")
	assert_str(out).not_contains(" ::1")


func test_the_account_name_goes_only_as_a_whole_word() -> void:
	var out := ReportWriter.scrub("deck logged in from steamdeck, Deck again", [], "deck")
	assert_str(out).is_equal("<user> logged in from steamdeck, <user> again")


func test_hosts_without_a_dot_and_long_ipv6_go_too() -> void:
	var log := "WARN net: Could not reach DESKTOP-AB12CD:7777.\nWARN net: Could not connect to allans-pc:7777 (Can't resolve)\nINFO net: Connecting to [2001:db8::1]:7777"
	var out := ReportWriter.scrub(log, [])
	assert_str(out).not_contains("DESKTOP")
	assert_str(out).not_contains("allans")
	assert_str(out).not_contains("db8")
	assert_str(out).not_contains("]")
	assert_str(out).contains("Could not reach <address>:7777")
