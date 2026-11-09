extends GdUnitTestSuite
## Profile zones add up per zone, and a zone that took no measurable time still reports.


func before_test() -> void:
	Prof.take()
	Prof.take_frame(100)


func test_zones_add_up_calls_and_worst() -> void:
	var t := Prof.start() - 2000
	Prof.stop(&"test/a", t)
	Prof.stop(&"test/a", Prof.start() - 500)
	var out := Prof.take()
	assert_int(int(out["test/a"]["calls"])).is_equal(2)
	assert_float(float(out["test/a"]["max_ms"])).is_greater_equal(2.0)
	assert_float(float(out["test/a"]["ms"])).is_greater_equal(2.5)
	assert_dict(Prof.take()).is_empty()


func test_a_zone_that_took_no_time_still_reports() -> void:
	# A start in the future clamps nothing; the point is a zero (or less) spend.
	Prof.stop(&"test/instant", Time.get_ticks_usec() + 1000)
	var out := Prof.take()
	assert_bool(out.has("test/instant")).is_true()
	assert_int(int(out["test/instant"]["calls"])).is_equal(1)
