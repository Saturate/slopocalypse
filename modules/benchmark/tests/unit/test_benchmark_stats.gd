extends GdUnitTestSuite
## Frame times summarise to average fps, the 1 % low (fps over the slowest hundredth of
## frames), p95 and worst; the worst hitches come out of a perf log slowest first, inside the
## measured window only.


func test_frame_times_give_fps_and_the_one_percent_low() -> void:
	var frames := PackedFloat32Array()
	for i in 99:
		frames.append(10.0)
	frames.append(50.0)
	var s := BenchmarkStats.summarise(frames)
	assert_int(int(s["frames"])).is_equal(100)
	assert_float(float(s["fps_mean"])).is_equal_approx(1000.0 / 10.4, 0.1)
	assert_float(float(s["fps_low_1pct"])).is_equal_approx(20.0, 0.01)
	assert_float(float(s["frame_ms_worst"])).is_equal(50.0)
	assert_float(float(s["frame_ms_p95"])).is_equal(10.0)


func test_no_frames_give_zeros() -> void:
	var s := BenchmarkStats.summarise(PackedFloat32Array())
	assert_int(int(s["frames"])).is_equal(0)
	assert_float(float(s["fps_mean"])).is_equal(0.0)


func test_worst_hitches_inside_the_window_slowest_first() -> void:
	var log := "\n".join([
		'{"t":5.0,"spike_ms":300.0,"zones":{"a":1.0}}',
		'{"t":20.0,"frames":60}',
		'{"t":21.0,"spike_ms":40.0,"zones":{"b":2.0}}',
		'{"t":30.0,"spike_ms":90.0,"zones":{"c":0.5},"compiles":{"draw":2}}',
		'{"t":80.0,"spike_ms":500.0,"zones":{}}',
		'not json',
	])
	var worst := BenchmarkStats.worst_hitches(log, 10.0, 70.0, 5)
	assert_int(worst.size()).is_equal(2)
	assert_float(float(worst[0]["ms"])).is_equal(90.0)
	assert_dict(worst[0]["compiles"]).is_equal({"draw": 2.0})
	assert_float(float(worst[1]["ms"])).is_equal(40.0)


func test_p95_on_small_runs_is_the_right_rank() -> void:
	assert_float(float(BenchmarkStats.summarise(PackedFloat32Array([30.0]))["frame_ms_p95"])).is_equal(30.0)
	var twenty := PackedFloat32Array()
	for i in 20:
		twenty.append(float(i + 1))
	# 95 % of 20 frames is 19: the 19th slowest-first rank, 19 ms.
	assert_float(float(BenchmarkStats.summarise(twenty)["frame_ms_p95"])).is_equal(19.0)


func test_the_short_summary_names_the_numbers_and_the_machine() -> void:
	var results := {"fps_mean": 87.4, "fps_low_1pct": 41.2, "frame_ms_worst": 52.3, "frames": 5200, "seconds": 60.0}
	var machine := {"version": "0.10.0", "gpu": "NVIDIA GeForce RTX 2070 SUPER", "renderer": "forward_plus (Vulkan)", "cpu": "AMD Ryzen 7 3700X", "os": "Windows 10", "resolution": "1920x1080"}
	var text := BenchmarkStats.summary_text(results, machine)
	for part in ["0.10.0", "87 fps", "41 fps", "52.3 ms", "RTX 2070 SUPER", "Vulkan", "Ryzen 7", "Windows 10", "1920x1080"]:
		assert_str(text).contains(part)
	# Short enough to paste in a chat line or two.
	assert_int(text.split("\n").size()).is_less_equal(2)


func test_the_short_summary_leaves_out_what_it_does_not_know() -> void:
	var text := BenchmarkStats.summary_text({"fps_mean": 60.0, "fps_low_1pct": 30.0, "frame_ms_worst": 40.0}, {"gpu": "", "os": "Linux"})
	assert_str(text).contains("Linux")
	assert_bool(text.contains(", ,") or text.ends_with(", ")).is_false()
