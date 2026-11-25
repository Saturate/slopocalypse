extends GdUnitTestSuite
## On a client, rounds and blasts that hit the water leave ripples; the newest few are kept.

const SQUARE := [[0.0, 0.0], [20.0, 0.0], [20.0, 20.0], [0.0, 20.0]]


func _view() -> WaterView:
	var view: WaterView = auto_free(WaterView.new())
	view.water = WaterBodies.new({"bodies": [{"outline": SQUARE, "depth": 2.0}], "freeboard": 0.0}, func(_x: float, _z: float) -> float: return 1.0)
	add_child(view)
	return view


func test_a_round_into_the_water_ripples_it_and_one_beside_it_does_not() -> void:
	var view := _view()
	EventBus.publish(&"weapon.fired", {"from": Vector3(10, 5, -10), "to": Vector3(10, -1, 10)})
	assert_int(view.ripple_count()).is_equal(1)
	EventBus.publish(&"weapon.fired", {"from": Vector3(30, 5, -10), "to": Vector3(30, -1, 10)})
	assert_int(view.ripple_count()).is_equal(1)


func test_a_blast_in_the_water_ripples_it() -> void:
	var view := _view()
	EventBus.publish(&"explosion", {"position": Vector3(10, 0.5, 10), "radius": 3.0})
	assert_int(view.ripple_count()).is_greater(0)


func test_only_the_newest_ripples_are_kept() -> void:
	var view := _view()
	for i in 40:
		view.add_ripple(Vector3(float(i % 20), 1.0, 5.0), 0.5)
	assert_int(view.ripple_count()).is_equal(WaterView.MAX_RIPPLES)


func test_a_flooded_crater_gets_a_surface() -> void:
	var view := _view()
	var before := view.get_child_count()
	view.add_puddle(Vector4(25.0, 10.0, 1.5, 1.0))
	assert_int(view.get_child_count()).is_equal(before + 1)


func test_a_poured_puddle_lies_on_the_ground_facing_up() -> void:
	var view := _view()
	view.drape("t", Vector3(40, 0, 40), 2.0, func(_x: float, _z: float) -> float: return 3.0)
	var part := view.get_node_or_null(^"Drape_t") as MeshInstance3D
	assert_object(part).is_not_null()
	var faces := part.mesh.get_faces()
	assert_float(faces[0].y).is_equal_approx(3.04, 0.001)
	assert_float(Plane(faces[0], faces[1], faces[2]).normal.y).is_greater(0.99)
	# Poured again, bigger: replaced, not added.
	var before := view.get_child_count()
	view.drape("t", Vector3(40, 0, 40), 3.0, func(_x: float, _z: float) -> float: return 3.0)
	assert_int(view.get_child_count()).is_equal(before)


func test_the_sea_reaches_the_horizon_from_high_ground() -> void:
	WorldMaps.clear()
	assert_bool(WorldMaps.select_default()).is_true()
	var shape := WorldMaps.shape()
	var view: WaterView = auto_free(WaterView.new())
	view.water = shape.water
	view.config = (Data.load_json("res://modules/world/data/world.json") as Dictionary)["water"]
	add_child(view)
	var camera: Camera3D = auto_free(Camera3D.new())
	camera.far = 4000.0
	add_child(camera)
	camera.current = true
	var eye := shape.camp() + Vector3(0.0, 120.0, 0.0)
	camera.global_position = eye
	await get_tree().process_frame
	var band := view.horizon()
	assert_object(band).is_not_null()
	var box := band.global_transform * band.get_aabb()
	var sea := shape.sea_level()
	# From under the sea's surface up to eye level, where an endless sea meets the sky.
	assert_float(box.position.y).is_less(sea)
	assert_float(box.end.y).is_equal_approx(eye.y, 0.01)
	# Drawn inside the far plane, and the sea's surface reaches it every way round, so no sky
	# shows between them.
	var r := box.size.x / 2.0
	assert_float(r).is_less(camera.far)
	var outer: Rect2 = shape.water.bodies[(shape.water as MapWater).sea]["box"]
	for a in 16:
		var p := Vector2(eye.x, eye.z) + Vector2.from_angle(TAU * a / 16.0) * r
		assert_bool(outer.has_point(p)).override_failure_message("the sea stops short of the horizon band at %s" % p).is_true()
	# A camera that sees further than the sea's surface reaches still gets it up to the band.
	camera.far = 20000.0
	await get_tree().process_frame
	box = band.global_transform * band.get_aabb()
	for a in 16:
		var p := Vector2(eye.x, eye.z) + Vector2.from_angle(TAU * a / 16.0) * box.size.x / 2.0
		assert_bool(outer.has_point(p)).override_failure_message("the sea stops short of a far camera's horizon band at %s" % p).is_true()
	# It goes with the camera.
	camera.global_position = eye + Vector3(300.0, -100.0, 0.0)
	await get_tree().process_frame
	box = band.global_transform * band.get_aabb()
	assert_float(box.get_center().x).is_equal_approx(eye.x + 300.0, 0.01)
	assert_float(box.end.y).is_equal_approx(eye.y - 100.0, 0.01)
	WorldMaps.clear()
