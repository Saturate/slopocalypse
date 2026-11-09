extends GdUnitTestSuite
## The perf module writes one JSON line per sample with the numbers we read later, including
## custom monitors other modules register.

const DIR := "user://perf-test"


func after_test() -> void:
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(f))
	if Performance.has_custom_monitor(&"test/answer"):
		Performance.remove_custom_monitor(&"test/answer")


func test_it_logs_samples_with_engine_and_custom_numbers() -> void:
	Performance.add_custom_monitor(&"test/answer", func() -> int: return 42)
	var perf: Node = auto_free((load("res://modules/perf/perf_module.gd") as GDScript).new())
	perf.set(&"log_dir", DIR)
	add_child(perf)
	await get_tree().create_timer(float(perf.get(&"config")["sample_seconds"]) * 1.5).timeout
	var path: String = perf.call(&"log_path")
	assert_bool(FileAccess.file_exists(path)).is_true()
	var lines := FileAccess.get_file_as_string(path).strip_edges().split("\n")
	assert_int(lines.size()).is_greater_equal(1)
	var rec: Dictionary = JSON.parse_string(lines[0])
	for key in ["t", "role", "frames", "frame_ms_mean", "frame_ms_p95", "frame_ms_max", "fps", "physics_ms", "nodes", "memory_mb"]:
		assert_bool(rec.has(key)).override_failure_message("missing " + key).is_true()
	assert_int(int(rec["frames"])).is_greater(0)
	assert_float(float((rec["custom"] as Dictionary)["test/answer"])).is_equal(42.0)
	# The newest sample is what other code (overlay, debug API) reads.
	assert_dict(perf.call(&"latest")).is_not_empty()
