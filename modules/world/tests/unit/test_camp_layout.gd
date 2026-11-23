extends GdUnitTestSuite
## The players' camp layout (#420): the same inputs give the same camp, the fence stands on
## the pad every map recipe levels for it, and everything the camp holds stands inside the
## fence, clear of the gate's lane and of each other.

const RECIPES := ["res://modules/world/data/maps/grassland.json", "res://modules/world/data/maps/mixed.json"]
const WAYS: Array[Vector3] = [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]
## Metres any spot keeps from the fence, and two spots from each other.
const ROOM := 1.5
## Half the players' car's width and a hand's breadth: it must clear the gateposts.
const CAR_HALF_WIDTH := 1.2


func _cfg() -> Dictionary:
	return (Data.load_json(CampLayout.CONFIG) as Dictionary)["camp"]


func _pad(recipe: String, centre: Vector3) -> Rect2:
	var side := float((Data.load_json(recipe) as Dictionary)["settlements"]["camp"]["size"])
	return Rect2(Vector2(centre.x, centre.z) - Vector2.ONE * side / 2.0, Vector2.ONE * side)


func test_the_config_is_whole() -> void:
	assert_str(CampLayout.check(_cfg())).is_empty()


func test_the_same_inputs_give_the_same_camp() -> void:
	var centre := Vector3(312.5, 41.0, -870.25)
	var a := CampLayout.make(centre, Vector3.LEFT, _pad(RECIPES[0], centre), _cfg())
	var b := CampLayout.make(centre, Vector3.LEFT, _pad(RECIPES[0], centre), _cfg())
	for name in CampLayout.SPOTS:
		assert_bool(a.spot(name).is_equal_approx(b.spot(name))).override_failure_message(name + " moved").is_true()
	assert_vector(a.gate()).is_equal(b.gate())
	assert_int(a.fence_runs().size()).is_equal(b.fence_runs().size())


func test_it_fits_its_pad_on_every_recipe_facing_every_way() -> void:
	var cfg := _cfg()
	var centre := Vector3(-140.0, 12.0, 600.0)
	for recipe: String in RECIPES:
		for way in WAYS:
			var where := "%s facing %s" % [recipe.get_file(), way]
			var camp := CampLayout.make(centre, way, _pad(recipe, centre), cfg)
			for run in camp.fence_runs():
				for end in run:
					assert_bool(camp.pad.grow(-0.5).has_point(Vector2(end.x, end.z))).override_failure_message(where + ": fence off the pad").is_true()
					assert_float(end.y).is_equal(centre.y)
			var gate := camp.gate()
			assert_float(Vector2(gate.x - centre.x, gate.z - centre.z).normalized().dot(Vector2(way.x, way.z))).is_equal_approx(1.0, 0.001)
			var placed: Array[Vector3] = []
			for name in CampLayout.SPOTS:
				var at := camp.spot(name).origin
				assert_bool(camp.inside(at, ROOM)).override_failure_message("%s: %s outside the fence" % [where, name]).is_true()
				assert_float(at.y).is_equal(centre.y)
				for other in placed:
					assert_float(other.distance_to(at)).override_failure_message("%s: %s on top of another" % [where, name]).is_greater(ROOM * 2.0)
				placed.append(at)
			# The hut's whole floor is inside, and its door looks the way the config says.
			var hut := camp.spot("hut")
			for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var p := hut * Vector3(corner.x * camp.hut_size.x / 2.0, 0.0, corner.y * camp.hut_size.y / 2.0)
				assert_bool(camp.inside(p, 0.4)).override_failure_message(where + ": hut through the fence").is_true()
			# Cars noses (+z) at the gate, the board's and stall's fronts (-z) toward it.
			for name: String in ["car", "transport"]:
				assert_float(camp.spot(name).basis.z.dot(camp.out)).is_greater(0.99)
			for name: String in ["board", "trader", "hut"]:
				assert_float((-camp.spot(name).basis.z).dot(camp.out)).is_greater(0.99)


func test_the_gate_lane_is_clear_for_a_car() -> void:
	var cfg := _cfg()
	var camp := CampLayout.make(Vector3.ZERO, Vector3.FORWARD, _pad(RECIPES[0], Vector3.ZERO), cfg)
	# Nothing parked or standing in the gate's width from the gate to the cars' row but the
	# players' car, which drives straight out through it.
	for name: String in ["hut", "board", "trader", "transport"]:
		var l := camp.local_of(camp.spot(name).origin)
		var in_lane := absf(l.x) < camp.gate_width / 2.0 + ROOM and l.y > 0.0
		assert_bool(in_lane).override_failure_message(name + " in the gate's lane").is_false()
	var car := camp.local_of(camp.spot("car").origin)
	assert_float(absf(car.x) + CAR_HALF_WIDTH).is_less(camp.gate_width / 2.0)


func test_inside_and_distance_agree_with_the_fence() -> void:
	var camp := CampLayout.make(Vector3(10.0, 0.0, 10.0), Vector3.RIGHT, Rect2(-20, -20, 60, 60), _cfg())
	assert_bool(camp.inside(camp.centre)).is_true()
	assert_float(camp.distance(camp.centre)).is_equal(0.0)
	var past := camp.point(Vector2(0.0, camp.half + 5.0))
	assert_bool(camp.inside(past)).is_false()
	assert_float(camp.distance(past)).is_equal_approx(5.0, 0.001)
	assert_bool(camp.in_gate(camp.gate(), 0.5)).is_true()
	assert_bool(camp.in_gate(camp.point(Vector2(camp.gate_width, camp.half)), 0.5)).is_false()


func test_around_puts_its_respawn_on_the_given_spot() -> void:
	var at := Vector3(5.0, 2.0, -7.0)
	var camp := CampLayout.around(at, Vector3.FORWARD, _cfg())
	assert_bool(camp.spot("respawn").origin.is_equal_approx(at)).is_true()
	assert_bool(camp.inside(at, ROOM)).is_true()
	var payload_camp := CampLayout.of_ready({"spawn": at + Vector3.UP})
	assert_bool(payload_camp.spot("respawn").origin.is_equal_approx(at)).is_true()
	assert_object(CampLayout.of_ready({"camp": camp})).is_same(camp)
