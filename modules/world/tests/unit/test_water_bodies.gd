extends GdUnitTestSuite
## Ponds are a flat level inside an outline; how deep it is anywhere comes from that and the
## ground, so the server and every client agree without sending anything.

const SQUARE := [[0.0, 0.0], [20.0, 0.0], [20.0, 20.0], [0.0, 20.0]]


func _water(ground: Callable) -> WaterBodies:
	return WaterBodies.new({"bodies": [{"outline": SQUARE, "depth": 2.0}], "shore": 4.0, "freeboard": 0.2}, ground)


func test_the_level_sits_just_under_the_lowest_bank() -> void:
	# The bank is lower toward +x.
	var w := _water(func(x: float, _z: float) -> float: return 5.0 - x * 0.1)
	assert_float(w.level_of(0)).is_equal_approx(5.0 - 2.0 - 0.2, 0.0001)


func test_depth_is_zero_outside_and_level_less_ground_inside() -> void:
	var w := _water(func(_x: float, _z: float) -> float: return 1.0)
	assert_float(w.depth(-5.0, 10.0, 0.0)).is_equal(0.0)
	assert_float(w.depth(10.0, 10.0, 0.0)).is_equal_approx(0.8, 0.0001)
	assert_float(w.depth(10.0, 10.0, 2.0)).is_equal(0.0)


func test_the_bed_slopes_down_from_the_edge_to_full_depth() -> void:
	var w := _water(func(_x: float, _z: float) -> float: return 1.0)
	var level := w.level_of(0)
	# At the edge it meets the bank; past `shore` metres in it is `depth` down.
	assert_float(w.carve(0.01, 10.0, 1.0)).is_equal_approx(level, 0.01)
	assert_float(w.carve(10.0, 10.0, 1.0)).is_equal_approx(level - 2.0, 0.0001)
	var half_way := w.carve(2.0, 10.0, 1.0)
	assert_float(half_way).is_less(level)
	assert_float(half_way).is_greater(level - 2.0)
	# Outside it leaves the ground alone, and it never raises ground that is already lower.
	assert_float(w.carve(-1.0, 10.0, 1.0)).is_equal(1.0)
	assert_float(w.carve(10.0, 10.0, -9.0)).is_equal(-9.0)


func test_the_surface_mesh_covers_the_outline_facing_up() -> void:
	var outline := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])
	var mesh := WaterView.surface_mesh(outline, 3.0)
	assert_object(mesh).is_not_null()
	var aabb := mesh.get_aabb()
	assert_vector(aabb.position).is_equal_approx(Vector3(0, 3, 0), Vector3.ONE * 0.001)
	assert_vector(aabb.size).is_equal_approx(Vector3(10, 0, 10), Vector3.ONE * 0.001)
	var faces := mesh.get_faces()
	var normal := Plane(faces[0], faces[1], faces[2]).normal
	assert_float(normal.y).is_greater(0.99)
