extends GdUnitTestSuite
## Profile zones add up per zone, and a zone that took no measurable time still reports.
## Covered time is how much of the clock any zone was running: nested zones count once.


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


func test_covered_time_counts_nested_zones_once() -> void:
	var before := Prof.covered_usec()
	# Well after any zone already closed: one that ended inside these stretches (the net gate's
	# on a node just added) would merge with them and change the covered time.
	var now := Time.get_ticks_usec() + 1_000_000
	# A 4 ms zone inside a 10 ms one (the inner closes first): 10 ms of the frame are covered.
	Prof.stop_at(&"test/inner", now - 6000, now - 2000)
	Prof.stop_at(&"test/outer", now - 10000, now)
	assert_int(Prof.covered_usec() - before).is_equal(10000)


func test_covered_time_adds_zones_one_after_another() -> void:
	var before := Prof.covered_usec()
	# Well after any zone already closed: one that ended inside these stretches (the net gate's
	# on a node just added) would merge with them and change the covered time.
	var now := Time.get_ticks_usec() + 1_000_000
	Prof.stop_at(&"test/a", now - 9000, now - 8000)
	Prof.stop_at(&"test/b", now - 5000, now - 3000)
	assert_int(Prof.covered_usec() - before).is_equal(3000)


func test_an_outer_zone_closing_after_inner_ones_adds_only_its_own_time() -> void:
	var before := Prof.covered_usec()
	# Well after any zone already closed: one that ended inside these stretches (the net gate's
	# on a node just added) would merge with them and change the covered time.
	var now := Time.get_ticks_usec() + 1_000_000
	Prof.stop_at(&"test/inner", now - 8000, now - 7000)
	Prof.stop_at(&"test/inner", now - 5000, now - 4000)
	Prof.stop_at(&"test/outer", now - 10000, now - 1000)
	assert_int(Prof.covered_usec() - before).is_equal(9000)
