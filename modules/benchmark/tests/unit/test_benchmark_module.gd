extends GdUnitTestSuite
## The menu starts the benchmark with its flag and the data's session; outside such a session
## the module does nothing; a finished run writes its numbers where asked; the results screen
## shows any results without errors.

const MODULE := "res://modules/benchmark/benchmark_module.gd"
const OUT := "user://test_benchmark_results.json"


func after_test() -> void:
	DirAccess.remove_absolute(OUT)


func test_the_session_is_the_flag_plus_the_data_args() -> void:
	var args: PackedStringArray = (load(MODULE) as GDScript).call(&"session_args")
	assert_str(args[0]).is_equal("--benchmark")
	assert_bool(args.has("--start=city")).is_true()
	assert_bool(args.has("--no-save")).is_true()


func test_it_sleeps_outside_a_benchmark_session() -> void:
	var module: Node = auto_free((load(MODULE) as GDScript).new())
	add_child(module)
	assert_bool(bool(module.get(&"active"))).is_false()
	assert_bool(module.is_processing()).is_false()


func test_a_finished_run_writes_its_numbers() -> void:
	var module: Node = auto_free((load(MODULE) as GDScript).new())
	add_child(module)
	module.set(&"out_path", OUT)
	module.set(&"_frames", PackedFloat32Array([16.0, 17.0, 40.0]))
	module.call(&"finish")
	var written: Variant = JSON.parse_string(FileAccess.get_file_as_string(OUT))
	assert_int(int((written as Dictionary)["frames"])).is_equal(3)
	assert_float(float((written as Dictionary)["frame_ms_worst"])).is_equal(40.0)


func test_the_results_screen_shows_numbers_and_hitches() -> void:
	var screen := BenchmarkResults.new()
	add_child(auto_free(screen))
	var results := BenchmarkStats.summarise(PackedFloat32Array([16.0, 17.0, 40.0]))
	results["draw_calls"] = 900.0
	results["hitches"] = [{"t": 30.0, "ms": 90.0, "zones": {"world/x": 2.5, "audio/y": 0.1}, "compiles": {"draw": 2.0}}]
	screen.show_results(results, false)
	assert_bool(screen.is_open()).is_true()
	UiStack.pop(screen)
