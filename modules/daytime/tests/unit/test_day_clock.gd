extends GdUnitTestSuite
## The clock: hours wrap, nights run faster, the light rises and sets, and the look blends
## between keys (including across midnight).

var _clock: DayClock


func before_test() -> void:
	_clock = DayClock.from_data()


func test_data_loads() -> void:
	assert_object(_clock).is_not_null()
	assert_float(_clock.hour).is_equal(float(_clock.config["start_hour"]))


func test_hours_wrap_past_midnight() -> void:
	_clock.set_hour(23.5)
	_clock.advance(float(_clock.config["hour_seconds"]) / float(_clock.config["night_speed"]))
	assert_float(_clock.hour).is_equal_approx(0.5, 0.001)
	_clock.set_hour(-1.0)
	assert_float(_clock.hour).is_equal_approx(23.0, 0.001)


func test_night_runs_faster_than_day() -> void:
	_clock.set_hour(12.0)
	var day := _clock.rate()
	_clock.set_hour(1.0)
	assert_float(_clock.rate()).is_equal_approx(day * float(_clock.config["night_speed"]), 0.000001)


func test_an_hour_of_day_takes_hour_seconds() -> void:
	_clock.set_hour(10.0)
	_clock.advance(float(_clock.config["hour_seconds"]))
	assert_float(_clock.hour).is_equal_approx(11.0, 0.001)


func test_the_sun_is_highest_at_midday_and_low_at_dawn() -> void:
	var rise: float = _clock.config["sunrise"]
	var dusk: float = _clock.config["sunset"]
	_clock.set_hour((rise + dusk) / 2.0)
	var noon := _down(_clock.light_basis())
	_clock.set_hour(rise + 0.2)
	var dawn := _down(_clock.light_basis())
	assert_float(noon).is_greater(dawn)
	# Never flat along the ground, so shadows don't stretch forever.
	assert_float(dawn).is_greater(0.0)


func test_the_light_always_points_down() -> void:
	for i in 48:
		_clock.set_hour(float(i) / 2.0)
		assert_float(_down(_clock.light_basis())).is_greater(0.0)


func test_night_is_dark_and_day_is_bright() -> void:
	_clock.set_hour(1.0)
	var night := _clock.look()
	_clock.set_hour(13.0)
	var day := _clock.look()
	assert_float(float(night["light_energy"])).is_less(float(day["light_energy"]))
	assert_float((night["sky_top"] as Color).get_luminance()).is_less((day["sky_top"] as Color).get_luminance())
	assert_float(float(night["stars"])).is_equal(1.0)
	assert_float(float(day["stars"])).is_equal(0.0)


func test_the_look_blends_smoothly_across_midnight() -> void:
	_clock.set_hour(23.99)
	var late: float = _clock.look()["light_energy"]
	_clock.set_hour(0.01)
	var early: float = _clock.look()["light_energy"]
	assert_float(absf(early - late)).is_less(0.01)


func test_the_look_never_jumps() -> void:
	var previous := {}
	for i in 24 * 60:
		_clock.set_hour(float(i) / 60.0)
		var look := _clock.look()
		if not previous.is_empty():
			assert_float(absf(float(look["light_energy"]) - float(previous["light_energy"]))).is_less(0.05)
		previous = look


## How far the light's direction points towards the ground.
func _down(basis: Basis) -> float:
	return (-basis.z).dot(Vector3.DOWN)
