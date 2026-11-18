extends GdUnitTestSuite
## The counters: kills by kind and faction, deaths by cause, the longest kill, totals.


func test_kills_count_by_kind_and_faction_and_keep_the_longest() -> void:
	var s := KillStats.new()
	s.record_kill("ann", "soldier", "militia", 80.0)
	s.record_kill("ann", "soldier", "regulars", 220.0)
	s.record_kill("ann", "drone", "", 40.0)
	assert_float(s.value("ann", "kills.soldier")).is_equal(2.0)
	assert_float(s.value("ann", "kills.soldier.militia")).is_equal(1.0)
	assert_float(s.value("ann", "kills.drone")).is_equal(1.0)
	assert_float(s.value("ann", KillStats.LONGEST)).is_equal(220.0)
	assert_float(s.value("bob", "kills.soldier")).is_equal(0.0)


func test_deaths_count_by_cause() -> void:
	var s := KillStats.new()
	s.record_death("ann", "soldier")
	s.record_death("ann", "self")
	assert_float(s.value("ann", "deaths")).is_equal(2.0)
	assert_float(s.value("ann", "deaths.self")).is_equal(1.0)


func test_totals_add_counts_and_keep_the_longest() -> void:
	var s := KillStats.new()
	s.record_kill("ann", "soldier", "militia", 50.0)
	s.record_kill("bob", "soldier", "militia", 300.0)
	var t := s.totals()
	assert_float(float(t["kills.soldier"])).is_equal(2.0)
	assert_float(float(t[KillStats.LONGEST])).is_equal(300.0)


func test_saved_counts_round_trip_and_never_go_negative() -> void:
	var s := KillStats.new()
	s.set_of("ann", {"kills.player": 3.0, "deaths": -4.0})
	assert_float(s.value("ann", "kills.player")).is_equal(3.0)
	assert_float(s.value("ann", "deaths")).is_equal(0.0)


func test_the_screen_shows_metres_for_the_longest_kill() -> void:
	assert_str(StatsScreen.shown({"longest_kill": 212.4}, "longest_kill")).is_equal("212 m")
	assert_str(StatsScreen.shown({"kills.soldier": 7.0}, "kills.soldier")).is_equal("7")
