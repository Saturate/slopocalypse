extends GdUnitTestSuite
## Glowstick rules (#447): which soldiers carry one comes from the data share, a carrier shows
## it only at night on patrol, and the stick takes its carrier's armband colour.

var _cfg: Dictionary


func before_test() -> void:
	_cfg = Data.load_json(GlowstickRules.CONFIG)
	Armband.use_config(Data.load_json(Armband.CONFIG))


func test_the_data_is_complete() -> void:
	assert_bool(Data.require(GlowstickRules.CONFIG, _cfg, GlowstickRules.REQUIRED)).is_true()


func test_the_night_share_of_soldiers_carries_one() -> void:
	var share := float(_cfg["enemy_night_share"])
	assert_float(share).is_greater(0.0)
	assert_float(share).is_less(1.0)
	var carrying := 0
	var tries := 1000
	for i in tries:
		if GlowstickRules.soldier_carries((float(i) + 0.5) / tries, share):
			carrying += 1
	assert_float(float(carrying) / tries).is_equal_approx(share, 0.002)
	assert_bool(GlowstickRules.soldier_carries(0.99, 0.0)).is_false()
	assert_bool(GlowstickRules.soldier_carries(0.0, 0.0)).is_false()


func test_a_carrier_shows_it_only_at_night_on_patrol() -> void:
	assert_bool(GlowstickRules.soldier_shows(true, true, true)).is_true()
	assert_bool(GlowstickRules.soldier_shows(true, false, true)).override_failure_message("by day").is_false()
	assert_bool(GlowstickRules.soldier_shows(true, true, false)).override_failure_message("fighting or stalking").is_false()
	assert_bool(GlowstickRules.soldier_shows(false, true, true)).override_failure_message("carries none").is_false()


func test_the_colour_is_the_carriers_band() -> void:
	var cfg := Armband.config()
	var player: Node = auto_free(Node.new())
	var civilian: Node = auto_free(Node.new())
	civilian.set_meta(&"civilian", true)
	var militia: Node = auto_free(Node.new())
	militia.set_meta(&"faction", "militia")
	militia.set_meta(&"team", "militia")
	var plain: Node = auto_free(Node.new())
	plain.set_meta(&"team", "enemies")
	for pair: Array in [[player, cfg["players"]], [civilian, cfg["civilians"]], [militia, (cfg["factions"] as Dictionary)["militia"]], [plain, cfg["enemies"]]]:
		var person: Node = pair[0]
		assert_that(GlowstickRules.colour_for(person)).is_equal(Armband.colour_for(person))
		var rgb: Array = pair[1]
		assert_that(GlowstickRules.colour_for(person)).is_equal(Color(float(rgb[0]), float(rgb[1]), float(rgb[2])))
