extends GdUnitTestSuite
## A plume's size, place and thickness at any age, which the server and clients both work
## out from the same spawn payload.


func _volume() -> SmokeVolume:
	return SmokeVolume.from_payload({
		"id": 7, "source": "blast", "position": Vector3(10, 0, 0), "r0": 1.0, "r1": 5.0,
		"grow": 4.0, "lifetime": 30.0, "density": 0.6, "wind": Vector3(1, 0, 0.5), "rise": 0.5, "seed": 3,
	})


func test_it_grows_from_r0_to_r1_easing_out() -> void:
	var v := _volume()
	assert_float(v.radius_at(0.0)).is_equal_approx(1.0, 0.0001)
	# Half way through growing it is three quarters of the way there.
	assert_float(v.radius_at(2.0)).is_equal_approx(4.0, 0.0001)
	assert_float(v.radius_at(4.0)).is_equal_approx(5.0, 0.0001)
	assert_float(v.radius_at(100.0)).is_equal_approx(5.0, 0.0001)


func test_it_drifts_with_the_wind_and_rises() -> void:
	var v := _volume()
	assert_vector(v.centre_at(0.0)).is_equal(Vector3(10, 0, 0))
	assert_vector(v.centre_at(10.0)).is_equal_approx(Vector3(20, 5, 5), Vector3.ONE * 0.0001)


func test_it_thins_over_the_last_third_of_its_life() -> void:
	var v := _volume()
	assert_float(v.density_at(0.0)).is_equal_approx(0.6, 0.0001)
	assert_float(v.density_at(20.0)).is_equal_approx(0.6, 0.0001)
	assert_float(v.density_at(25.0)).is_equal_approx(0.3, 0.0001)
	assert_float(v.density_at(30.0)).is_equal(0.0)


func test_the_payload_round_trips() -> void:
	var v := _volume()
	var back := SmokeVolume.from_payload(v.to_payload())
	assert_dict(back.to_payload()).is_equal(v.to_payload())


func test_smoke_along_a_line_is_density_times_length_inside() -> void:
	var v := _volume()
	v.age = 4.0
	var c := v.centre_at(4.0)
	# Straight through the middle: the whole diameter.
	assert_float(v.along(c + Vector3(-20, 0, 0), c + Vector3(20, 0, 0))).is_equal_approx(0.6 * 10.0, 0.001)
	# Passing beside it: none.
	assert_float(v.along(c + Vector3(-20, 0, 6), c + Vector3(20, 0, 6))).is_equal(0.0)
	# Stopping in the middle: half.
	assert_float(v.along(c + Vector3(-20, 0, 0), c)).is_equal_approx(0.6 * 5.0, 0.001)
	# Both ends inside.
	assert_float(v.along(c + Vector3(-1, 0, 0), c + Vector3(1, 0, 0))).is_equal_approx(0.6 * 2.0, 0.001)


func test_inside_length_is_a_chord() -> void:
	# 3-4-5: a line 3 m off the centre of a 5 m sphere spends 8 m inside.
	assert_float(SmokeVolume.inside_length(Vector3(-10, 3, 0), Vector3(10, 3, 0), Vector3.ZERO, 5.0)).is_equal_approx(8.0, 0.0001)
