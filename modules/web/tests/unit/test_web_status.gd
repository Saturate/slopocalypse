extends GdUnitTestSuite
## The status page: names are escaped, nothing secret shows, and parts of modules that are
## not loaded are left out.


func test_the_page_escapes_names_and_counts_players() -> void:
	var page := WebStatus.html({"name": "Slopocalypse", "version": "0.4.0", "uptime_seconds": 3700, "players": ["<script>x</script>", "Ranger"], "soldiers_alive": 3})
	assert_str(page).contains("Players online: 2")
	assert_str(page).contains("&lt;script&gt;")
	assert_bool(page.contains("<script>x</script>")).is_false()
	assert_str(page).contains("1h 1m")


func test_a_running_mission_and_the_board_show() -> void:
	var m := {"codename": "Operation Rusty Lantern", "kind": "Clean Sweep", "place": "Depot", "distance_m": 300, "pays": 370}
	var page := WebStatus.html({"players": [], "mission_state": "in_mission", "mission": m, "board": [m]})
	assert_str(page).contains("Out on Operation Rusty Lantern")
	assert_str(page).contains("On the board")


func test_the_status_holds_nothing_secret() -> void:
	var status := WebStatus.build(get_tree(), 0)
	var text := JSON.stringify(status)
	assert_bool(text.contains("key")).is_false()
	assert_bool(status.has("players")).is_true()
	# No missions module here: no mission parts.
	assert_bool(status.has("mission")).is_false()
