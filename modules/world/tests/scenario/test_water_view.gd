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
