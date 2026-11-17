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
