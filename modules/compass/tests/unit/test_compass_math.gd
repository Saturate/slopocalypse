extends GdUnitTestSuite
## The compass strip's maths (#455): bearings with north at -Z and east at +X, where a
## bearing lands on a strip showing `span` degrees around the heading, markers past the edge
## sticking to it, the fade up close, and initials for crowded names.

const SPAN := 180.0


func test_bearings_go_clockwise_from_north() -> void:
	var here := Vector3(10.0, 2.0, 10.0)
	assert_float(CompassMath.bearing(here, here + Vector3(0, 0, -5))).is_equal_approx(0.0, 0.001)
	assert_float(CompassMath.bearing(here, here + Vector3(5, 3, 0))).is_equal_approx(90.0, 0.001)
	assert_float(CompassMath.bearing(here, here + Vector3(0, -1, 5))).is_equal_approx(180.0, 0.001)
	assert_float(CompassMath.bearing(here, here + Vector3(-5, 0, 0))).is_equal_approx(270.0, 0.001)


func test_heading_is_where_the_camera_looks_on_the_ground() -> void:
	assert_float(CompassMath.heading(Basis.IDENTITY)).is_equal_approx(0.0, 0.001)
	# Turned to face east (+X) and looking down a little: still 90.
	var east := Basis(Vector3.UP, -PI / 2.0) * Basis(Vector3.RIGHT, -0.4)
	assert_float(CompassMath.heading(east)).is_equal_approx(90.0, 0.001)


func test_a_bearing_ahead_sits_in_the_middle_and_one_to_the_side_off_centre() -> void:
	assert_float(float(CompassMath.place(30.0, 30.0, SPAN)["x"])).is_equal_approx(0.0, 0.001)
	assert_float(float(CompassMath.place(75.0, 30.0, SPAN)["x"])).is_equal_approx(0.5, 0.001)
	assert_float(float(CompassMath.place(345.0, 30.0, SPAN)["x"])).is_equal_approx(-0.5, 0.001)
	# Across north: heading 350, bearing 10 is 20 degrees to the right.
	assert_float(float(CompassMath.place(10.0, 350.0, SPAN)["x"])).is_equal_approx(20.0 / 90.0, 0.001)
	assert_bool(bool(CompassMath.place(75.0, 30.0, SPAN)["clamped"])).is_false()


func test_markers_past_the_edge_stick_to_it_pointing_out() -> void:
	var right := CompassMath.place(150.0, 0.0, SPAN)
	assert_float(float(right["x"])).is_equal(1.0)
	assert_bool(bool(right["clamped"])).is_true()
	var left := CompassMath.place(200.0, 0.0, SPAN)
	assert_float(float(left["x"])).is_equal(-1.0)
	assert_bool(bool(left["clamped"])).is_true()
	# Straight behind goes to the left edge, not the middle.
	assert_float(float(CompassMath.place(180.0, 0.0, SPAN)["x"])).is_equal(-1.0)


func test_markers_fade_out_up_close() -> void:
	assert_float(CompassMath.fade(2.0, 10.0, 5.0)).is_equal(0.0)
	assert_float(CompassMath.fade(12.5, 10.0, 5.0)).is_equal_approx(0.5, 0.001)
	assert_float(CompassMath.fade(300.0, 10.0, 5.0)).is_equal(1.0)


func test_initials_for_crowded_names() -> void:
	assert_str(CompassMath.initials("Ana Lopez")).is_equal("AL")
	assert_str(CompassMath.initials("ranger")).is_equal("R")
	assert_str(CompassMath.initials("  ")).is_equal("")


func test_crowded_markers_are_found_by_screen_distance() -> void:
	var crowded := CompassMath.crowded(PackedFloat32Array([0.10, 0.12, 0.6]), 0.05)
	assert_array(crowded).contains_exactly([true, true, false])


func test_markers_on_one_spot_are_spread_apart_in_order() -> void:
	# Two stuck to the left end and one just inside it, one alone on the right.
	var out := CompassMath.spread([0.0, 0.0, 3.0, 200.0] as Array[float], 20.0, 0.0, 300.0)
	var left := out.slice(0, 2)
	left.sort()
	assert_array(left).contains_exactly([0.0, 20.0])
	assert_float(out[2]).is_equal(40.0)
	assert_float(out[3]).is_equal(200.0)


func test_spreading_at_the_right_end_pushes_inward() -> void:
	var out := CompassMath.spread([300.0, 300.0, 120.0] as Array[float], 20.0, 0.0, 300.0)
	assert_float(maxf(out[0], out[1])).is_equal(300.0)
	assert_float(minf(out[0], out[1])).is_equal(280.0)
	assert_float(out[2]).is_equal(120.0)
