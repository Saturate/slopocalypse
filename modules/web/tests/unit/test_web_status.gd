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


func test_the_kill_board_shows_totals_and_the_top_players() -> void:
	var kills := {"totals": {"soldiers": 41, "drones": 3, "players": 1, "civilians": 2, "deaths": 12, "headshots": 9, "longest_kill_m": 212},
		"top": [{"name": "<b>Ann</b>", "kills": 30, "headshots": 7, "longest_kill_m": 212}, {"name": "Bob", "kills": 15, "headshots": 2, "longest_kill_m": 80}]}
	var page := WebStatus.html({"players": [], "kills": kills})
	assert_str(page).contains("41")
	assert_str(page).contains("212 m")
	assert_str(page).contains("&lt;b&gt;Ann&lt;/b&gt;")
	assert_bool(page.contains("<b>Ann</b>")).is_false()
	assert_int(page.find("Ann")).is_less(page.find("Bob"))


func test_the_status_takes_the_kill_board_from_the_stats_module() -> void:
	var fake := FakeStats.new()
	add_child(fake)
	var status := WebStatus.build(get_tree(), 0)
	fake.free()
	var kills: Dictionary = status.get("kills", {})
	assert_int(int((kills["totals"] as Dictionary)["soldiers"])).is_equal(5)
	assert_int(int((kills["totals"] as Dictionary)["longest_kill_m"])).is_equal(120)
	assert_str(str((kills["top"] as Array)[0]["name"])).is_equal("Ann")
	# Without the stats module there is no board.
	assert_bool(WebStatus.build(get_tree(), 0).has("kills")).is_false()


## Stands in for the stats module's API (the `stats_api` group), so this suite does not
## depend on that module being there.
class FakeStats:
	extends Node

	func _init() -> void:
		add_to_group(&"stats_api")

	func server_totals() -> Dictionary:
		return {"kills.soldier": 5.0, "kills.soldier.militia": 5.0, "kills.drone": 1.0, "deaths": 2.0, "longest_kill": 120.4}

	func server_top(count: int) -> Array[Dictionary]:
		var rows: Array[Dictionary] = [{"name": "Ann", "kills": 6, "headshots": 1, "longest_kill": 120.4}]
		return rows if count > 0 else []

