extends GdUnitTestSuite
## A generated road read by distance along it (#472).

func _line() -> RoadLine:
	# An L: 10 m east, then 10 m south, rising a metre a step.
	return RoadLine.new({"kind": "track", "width": 3.5,
		"points": PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)]),
		"heights": PackedFloat32Array([0.0, 1.0, 2.0])})


func test_length_and_points_along_it() -> void:
	var line := _line()
	assert_float(line.length()).is_equal_approx(20.0, 0.001)
	assert_vector(line.point_at(5.0)).is_equal_approx(Vector2(5, 0), Vector2.ONE * 0.001)
	assert_vector(line.point_at(15.0)).is_equal_approx(Vector2(10, 5), Vector2.ONE * 0.001)
	assert_float(line.height_at(15.0)).is_equal_approx(1.5, 0.001)
	# Past the ends: held at them.
	assert_vector(line.point_at(-3.0)).is_equal_approx(Vector2(0, 0), Vector2.ONE * 0.001)
	assert_vector(line.point_at(99.0)).is_equal_approx(Vector2(10, 10), Vector2.ONE * 0.001)


func test_direction_and_across() -> void:
	var line := _line()
	assert_vector(line.direction_at(5.0)).is_equal_approx(Vector2(1, 0), Vector2.ONE * 0.001)
	# To the right of heading east is south (+z).
	assert_vector(line.across_at(5.0)).is_equal_approx(Vector2(0, 1), Vector2.ONE * 0.001)


func test_a_point_is_located_along_and_across() -> void:
	var line := _line()
	var at := line.locate(Vector2(4, 2), 0.0, 20.0)
	assert_float(at.x).is_equal_approx(4.0, 0.001)
	assert_float(at.y).is_equal_approx(2.0, 0.001)
	var left := line.locate(Vector2(4, -3), 0.0, 20.0)
	assert_float(left.y).is_equal_approx(-3.0, 0.001)
