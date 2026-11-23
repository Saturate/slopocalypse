extends GdUnitTestSuite
## Who fights whom: relations between factions, hostile below a line, the same faction
## never; players are everyone's enemy for now.


func _rules() -> FactionRules:
	return FactionRules.new(Data.load_json("res://modules/factions/data/factions.json"))


func test_relations_go_both_ways_and_a_faction_is_never_hostile_to_itself() -> void:
	var r := _rules()
	assert_float(r.relation("militia", "regulars")).is_equal(r.relation("regulars", "militia"))
	assert_bool(r.hostile("militia", "militia")).is_false()
	assert_float(r.relation("militia", "militia")).is_equal(100.0)


func test_hostile_below_the_line() -> void:
	var r := FactionRules.new({"factions": {"a": {}, "b": {}, "c": {}}, "relations": [["a", "b", -50.0], ["a", "c", -10.0]], "default_relation": 0.0, "hostile_below": -30.0})
	assert_bool(r.hostile("a", "b")).is_true()
	assert_bool(r.hostile("c", "a")).is_false()
	assert_bool(r.hostile("b", "c")).is_false()


func test_players_are_everyones_enemy_for_now() -> void:
	var r := _rules()
	for id: String in r.ids():
		assert_bool(r.hostile(id, FactionRules.PLAYERS)).is_true()
		assert_bool(r.hostile(FactionRules.PLAYERS, id)).is_true()
	assert_bool(r.hostile("", "militia")).is_false()


func test_squads_pick_factions_by_weight() -> void:
	var r := FactionRules.new({"factions": {"a": {"weight": 3.0}, "b": {"weight": 1.0}}, "relations": []})
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var counts := {"a": 0, "b": 0}
	for i in 4000:
		counts[r.pick(rng)] += 1
	assert_float(float(counts["a"]) / 4000.0).is_equal_approx(0.75, 0.03)


func _standing_rules() -> FactionRules:
	return FactionRules.new({
		"factions": {"a": {}, "b": {}, "c": {}},
		"relations": [["a", "b", -70.0], ["a", "c", 10.0]],
		"default_relation": 0.0, "hostile_below": -30.0, "friendly_above": 30.0, "allied_above": 70.0,
		"standing": {"start": {"c": 40.0}, "default_start": -50.0, "kill_member": -25.0, "hurt_member": -3.0, "kill_rival": 6.0},
	})


func test_bands() -> void:
	var r := _standing_rules()
	assert_str(r.band(-31.0)).is_equal("hostile")
	assert_str(r.band(0.0)).is_equal("neutral")
	assert_str(r.band(31.0)).is_equal("friendly")
	assert_str(r.band(71.0)).is_equal("allied")


func test_players_start_where_data_says_and_bands_decide_hostility() -> void:
	var r := _standing_rules()
	assert_float(r.standing("ann", "a")).is_equal(-50.0)
	assert_float(r.standing("ann", "c")).is_equal(40.0)
	assert_bool(r.hostile_to_player("a", "ann")).is_true()
	assert_bool(r.hostile_to_player("c", "ann")).is_false()


func test_a_kill_lowers_the_victims_side_and_raises_its_enemies() -> void:
	var r := _standing_rules()
	r.record_kill("ann", "a")
	assert_float(r.standing("ann", "a")).is_equal(-75.0)
	# b is hostile to a; c is not.
	assert_float(r.standing("ann", "b")).is_equal(-44.0)
	assert_float(r.standing("ann", "c")).is_equal(40.0)
	# Standing is per player.
	assert_float(r.standing("bob", "a")).is_equal(-50.0)


func test_standing_is_clamped_and_round_trips() -> void:
	var r := _standing_rules()
	for i in 10:
		r.record_kill("ann", "a")
	assert_float(r.standing("ann", "a")).is_equal(-100.0)
	var saved := r.standing_of("ann")
	var other := _standing_rules()
	other.set_standing_of("ann", saved)
	assert_float(other.standing("ann", "b")).is_equal(r.standing("ann", "b"))
	other.set_standing_of("ann", {"a": 500.0, "nobody": 3.0})
	assert_float(other.standing("ann", "a")).is_equal(100.0)
	assert_bool(other.standing_of("ann").has("nobody")).is_false()
