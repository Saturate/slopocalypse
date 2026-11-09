extends GdUnitTestSuite
## Frame times collected over a sample window come out as mean, 95th percentile and worst,
## and the window starts empty again after it is taken.


func test_frame_times_summarise_to_mean_p95_and_worst() -> void:
	var s := PerfSampler.new()
	for ms in range(1, 101):
		s.add_frame(float(ms))
	var out := s.take()
	assert_int(int(out["frames"])).is_equal(100)
	assert_float(float(out["frame_ms_mean"])).is_equal_approx(50.5, 0.001)
	assert_float(float(out["frame_ms_p95"])).is_equal_approx(95.0, 0.001)
	assert_float(float(out["frame_ms_max"])).is_equal(100.0)


func test_taking_a_sample_starts_a_new_window() -> void:
	var s := PerfSampler.new()
	s.add_frame(40.0)
	s.take()
	s.add_frame(10.0)
	var out := s.take()
	assert_int(int(out["frames"])).is_equal(1)
	assert_float(float(out["frame_ms_max"])).is_equal(10.0)


func test_an_empty_window_reports_zeros() -> void:
	var out := PerfSampler.new().take()
	assert_int(int(out["frames"])).is_equal(0)
	assert_float(float(out["frame_ms_mean"])).is_equal(0.0)


func test_old_logs_beyond_the_limit_are_the_oldest_names() -> void:
	var names: Array[String] = ["server-20261109-100000.ndjson", "client-20261109-090000.ndjson", "client-20261109-110000.ndjson", "notes.txt"]
	assert_array(PerfSampler.to_prune(names, 2)).contains_exactly(["client-20261109-090000.ndjson"])
	assert_array(PerfSampler.to_prune(names, 5)).is_empty()
