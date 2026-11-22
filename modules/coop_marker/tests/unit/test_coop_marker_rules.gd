extends GdUnitTestSuite
## Who gets a co-op marker and how strongly it shows (#447): only other living players, never
## yourself, enemies or civilians; hidden up close, faint when plainly in view, full through
## walls, gone past the range. Numbers come from the module's data, read here, not repeated.

const CONFIG := "res://modules/coop_marker/data/coop_marker.json"

var _config: Dictionary


func before() -> void:
	_config = Data.load_json(CONFIG)


func _person(groups: Array[StringName]) -> Node3D:
	var n: Node3D = auto_free(Node3D.new())
	for g in groups:
		n.add_to_group(g)
	add_child(n)
	return n


func _f(key: String) -> float:
	return float(_config[key])


func test_the_data_has_every_field() -> void:
	assert_bool(Data.require(CONFIG, _config, CoopMarkerRules.REQUIRED)).is_true()


func test_only_other_living_players_are_partners() -> void:
	var me := _person([&"players"])
	var ana := _person([&"players"])
	assert_bool(CoopMarkerRules.is_partner(ana, me)).is_true()
	assert_bool(CoopMarkerRules.is_partner(me, me)).override_failure_message("never yourself").is_false()
	assert_bool(CoopMarkerRules.is_partner(_person([]), me)).is_false()
	ana.set_meta(&"dead", true)
	assert_bool(CoopMarkerRules.is_partner(ana, me)).override_failure_message("not while dead").is_false()
	ana.set_meta(&"dead", false)
	ana.visible = false
	assert_bool(CoopMarkerRules.is_partner(ana, me)).is_false()


func test_enemies_and_civilians_never_get_one() -> void:
	var me := _person([&"players"])
	assert_bool(CoopMarkerRules.is_partner(_person([&"players", &"enemies"]), me)).is_false()
	assert_bool(CoopMarkerRules.is_partner(_person([&"players", &"civilians"]), me)).is_false()
	var tagged := _person([&"players"])
	tagged.set_meta(&"team", "raiders")
	assert_bool(CoopMarkerRules.is_partner(tagged, me)).is_false()
	var local := _person([&"players"])
	local.set_meta(&"civilian", true)
	assert_bool(CoopMarkerRules.is_partner(local, me)).is_false()


func test_a_partner_parked_hidden_in_a_car_still_counts() -> void:
	var me := _person([&"players"])
	var ana := _person([&"players"])
	ana.visible = false
	assert_bool(CoopMarkerRules.is_partner(ana, me, true)).is_true()


func test_through_a_wall_at_mid_range_it_shows_fully() -> void:
	var mid := (_f("hide_near_m") + _f("near_fade_m") + _f("range_m") - _f("range_fade_m")) * 0.5
	assert_float(CoopMarkerRules.alpha(mid, false, _config)).is_equal(1.0)


func test_up_close_it_fades_out() -> void:
	var near := _f("hide_near_m")
	assert_float(CoopMarkerRules.alpha(near * 0.5, false, _config)).is_equal(0.0)
	assert_float(CoopMarkerRules.alpha(near, false, _config)).is_equal(0.0)
	var halfway := CoopMarkerRules.alpha(near + _f("near_fade_m") * 0.5, false, _config)
	assert_float(halfway).is_greater(0.0)
	assert_float(halfway).is_less(1.0)
	assert_float(CoopMarkerRules.alpha(near + _f("near_fade_m"), false, _config)).is_equal(1.0)


func test_plainly_in_view_it_drops_to_the_faint_level() -> void:
	var inside := _f("in_view_m") - 1.0
	assert_float(CoopMarkerRules.alpha(inside, true, _config)).is_equal_approx(_f("in_view_alpha"), 0.0001)
	assert_float(CoopMarkerRules.alpha(inside, false, _config)).override_failure_message("behind a wall it stays full").is_equal(1.0)
	assert_float(CoopMarkerRules.alpha(_f("in_view_m") + 1.0, true, _config)).override_failure_message("in sight but far: full").is_equal(1.0)
	assert_float(_f("in_view_alpha")).is_greater(0.0)
	assert_float(_f("in_view_alpha")).is_less(1.0)


func test_past_the_range_it_is_gone_and_fades_before_it() -> void:
	var range_m := _f("range_m")
	assert_float(CoopMarkerRules.alpha(range_m + 1.0, false, _config)).is_equal(0.0)
	assert_float(CoopMarkerRules.alpha(range_m, false, _config)).is_equal(0.0)
	var edge := CoopMarkerRules.alpha(range_m - _f("range_fade_m") * 0.5, false, _config)
	assert_float(edge).is_greater(0.0)
	assert_float(edge).is_less(1.0)


func test_distance_is_whole_metres() -> void:
	assert_int(CoopMarkerRules.metres(41.6)).is_equal(42)
	assert_int(CoopMarkerRules.metres(0.2)).is_equal(0)
	assert_int(CoopMarkerRules.metres(-3.0)).is_equal(0)


func test_the_shown_alpha_eases_the_same_at_any_frame_rate() -> void:
	var rate := _f("fade_rate")
	var once := CoopMarkerRules.ease_alpha(0.0, 1.0, rate, 0.1)
	var twice := CoopMarkerRules.ease_alpha(CoopMarkerRules.ease_alpha(0.0, 1.0, rate, 0.05), 1.0, rate, 0.05)
	assert_float(twice).is_equal_approx(once, 0.0001)
	assert_float(once).is_greater(0.0)
	assert_float(once).is_less(1.0)
