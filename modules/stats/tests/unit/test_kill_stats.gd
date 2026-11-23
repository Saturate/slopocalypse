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


func test_the_top_players_by_kills_for_the_status_page() -> void:
	var s := KillStats.new()
	s.record_kill("ann", "soldier", "militia", 50.0)
	s.record_kill("ann", "drone", "", 90.0)
	s.add("ann", "headshots")
	s.record_kill("bob", "soldier", "militia", 300.0)
	s.record_kill("bob", "player", "", 10.0)
	s.record_kill("bob", "soldier", "regulars", 20.0)
	# Civilians are counted, but not towards the board.
	s.record_kill("cid", "civilian", "", 5.0)
	s.record_kill("cid", "civilian", "", 5.0)
	s.record_kill("cid", "civilian", "", 5.0)
	s.record_death("dee", "soldier")
	var top := s.top(2)
	assert_int(top.size()).is_equal(2)
	assert_str(str(top[0]["name"])).is_equal("bob")
	assert_int(int(top[0]["kills"])).is_equal(3)
	assert_float(float(top[0]["longest_kill"])).is_equal(300.0)
	assert_str(str(top[1]["name"])).is_equal("ann")
	assert_int(int(top[1]["headshots"])).is_equal(1)
	# Nobody with no kills makes the board.
	assert_array(s.top(10).map(func(r: Dictionary) -> String: return str(r["name"]))).contains_exactly(["bob", "ann"])
