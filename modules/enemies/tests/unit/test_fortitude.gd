extends GdUnitTestSuite
## Fortitude: the starting roll stays in range, each situation moves the total by a step,
## steady soldiers shrug off wounds, and the total's band says what they do.

const CFG := {
	"start": [6, 20], "step": 2, "steady_from": 18,
	"bands": {"fight": 17, "posture": 11, "flee": 5},
}


func test_rolls_stay_in_range() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 200:
		assert_int(Fortitude.roll(CFG, rng)).is_between(6, 20)


func test_allies_cover_and_leaders_raise_it_pinned_and_alone_lower_it() -> void:
	assert_int(Fortitude.total(CFG, 12, {"ally_in_sight": true})).is_equal(14)
	assert_int(Fortitude.total(CFG, 12, {})).is_equal(10)
	assert_int(Fortitude.total(CFG, 12, {"ally_in_sight": true, "in_cover": true})).is_equal(16)
	# Pinned outweighs cover.
	assert_int(Fortitude.total(CFG, 12, {"ally_in_sight": true, "in_cover": true, "pinned": true})).is_equal(12)
	assert_int(Fortitude.total(CFG, 12, {"ally_in_sight": true, "leader_in_sight": true})).is_equal(16)
	assert_int(Fortitude.total(CFG, 12, {"ally_in_sight": true, "leader_lost": true})).is_equal(12)


func test_steady_soldiers_shrug_off_wounds_and_empty_guns() -> void:
	assert_int(Fortitude.total(CFG, 12, {"ally_in_sight": true, "wounded": true, "out_of_ammo": true})).is_equal(10)
	assert_int(Fortitude.total(CFG, 18, {"ally_in_sight": true, "wounded": true, "out_of_ammo": true})).is_equal(20)


func test_bands() -> void:
	assert_str(Fortitude.band(CFG, 20)).is_equal(Fortitude.FIGHT)
	assert_str(Fortitude.band(CFG, 17)).is_equal(Fortitude.FIGHT)
	assert_str(Fortitude.band(CFG, 16)).is_equal(Fortitude.POSTURE)
	assert_str(Fortitude.band(CFG, 11)).is_equal(Fortitude.POSTURE)
	assert_str(Fortitude.band(CFG, 10)).is_equal(Fortitude.FLEE)
	assert_str(Fortitude.band(CFG, 5)).is_equal(Fortitude.FLEE)
	assert_str(Fortitude.band(CFG, 4)).is_equal(Fortitude.SUBMIT)
	assert_str(Fortitude.band(CFG, -3)).is_equal(Fortitude.SUBMIT)
