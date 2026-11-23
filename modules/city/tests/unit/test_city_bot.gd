extends GdUnitTestSuite
## The city walk (`--bot=city`): a ring round the middle block along the inner streets'
## centre lines, corner by corner, so the benchmark sees every side of the square.

const CFG := {
	"size": 150.0, "blocks": 3, "street_width": 8.0, "avenue_width": 10.0, "street_jitter": 2.0, "pavement": 3.0,
	"passage_width": 3.0, "gateway_height": 3.2, "building_depth": 9.5, "floors_edge": 4, "floors_middle": 6, "style": "danish",
	"crossing_width": 3.0, "crossing_setback": 0.6, "lamp_spacing": 25.0, "lamp_inset": 0.5,
	"tree_spacing": 12.0, "tree_inset": 1.1, "tree_street_width": 10.0, "door_clear": 2.0, "spot_nudge": 3.0,
}


func test_route_rings_the_square_down_the_middle_of_its_streets() -> void:
	var plan := CityLayout.make(CFG, 5)
	var route := CityBot.route(plan)
	assert_int(route.size()).is_equal(4)
	var streets: Array = plan["streets"]
	for corner in route:
		# Each corner sits in a street on both axes: on an x-line and a z-line.
		var on_x := false
		var on_z := false
		for i in streets.size():
			var street: Rect2 = streets[i]
			if street.has_point(corner):
				if i % 2 == 0:
					on_x = true
				else:
					on_z = true
		assert_bool(on_x and on_z).override_failure_message("corner %s is not at a junction" % corner).is_true()
		# Inside the city, never on its outer ring.
		assert_float(absf(corner.x)).is_less(float(CFG["size"]) / 2.0 - float(CFG["street_width"]))
		assert_float(absf(corner.y)).is_less(float(CFG["size"]) / 2.0 - float(CFG["street_width"]))
	# A ring: the first and last corners share an axis, as do each pair of neighbours.
	for i in route.size():
		var a := route[i]
		var b := route[(i + 1) % route.size()]
		assert_bool(is_equal_approx(a.x, b.x) or is_equal_approx(a.y, b.y)).is_true()


func test_a_city_too_small_for_inner_streets_walks_its_outer_ring() -> void:
	var cfg := CFG.duplicate()
	cfg["blocks"] = 2
	var route := CityBot.route(CityLayout.make(cfg, 5))
	assert_int(route.size()).is_equal(4)
	for corner in route:
		assert_float(absf(corner.x)).is_greater(float(CFG["size"]) / 2.0 - float(CFG["street_width"]))


func test_no_plan_no_route() -> void:
	assert_int(CityBot.route({}).size()).is_equal(0)
