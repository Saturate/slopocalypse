extends GdUnitTestSuite
## Where the city's guards stand: behind street windows on upper floors, on flat roofs, at
## block corners on the pavement, and patrolling round blocks; the same for the same seed.

const COUNTS := {"window_posts": 8, "roof_posts": 3, "corner_posts": 4, "patrols": 2}


func _plan() -> Dictionary:
	var cfg: Dictionary = Data.load_json("res://modules/city/data/city.json")
	return CityLayout.make(cfg, int(cfg["seed"]))


func _spots(seed := 3) -> Dictionary:
	return CityGuards.spots(_plan(), COUNTS, seed)


func test_same_seed_same_guards() -> void:
	assert_str(var_to_str(_spots(3))).is_equal(var_to_str(_spots(3)))
	assert_str(var_to_str(_spots(3))).is_not_equal(var_to_str(_spots(4)))


func test_window_posts_are_inside_a_building_behind_its_street_wall_looking_out() -> void:
	var s := _spots()
	var windows: Array = s["windows"]
	assert_int(windows.size()).is_equal(8)
	for w: Dictionary in windows:
		var at: Vector3 = w["at"]
		var b: Dictionary = w["building"]
		var foot: Rect2 = b["footprint"]
		assert_bool(foot.has_point(Vector2(at.x, at.z))).is_true()
		# Above the ground floor.
		assert_float(at.y).is_greater(VoxApartment.STOREY)
		# Looking the way the building faces (its street).
		var look := Vector3.FORWARD.rotated(Vector3.UP, float(w["yaw"]))
		var facing: Vector2 = b["facing"]
		assert_float(Vector2(look.x, look.z).dot(facing)).is_greater(0.99)


func test_corner_posts_and_patrols_are_on_pavements() -> void:
	var s := _spots()
	var plan := _plan()
	var on_pavement := func(p: Vector3) -> bool:
		for block: Rect2 in plan["blocks"]:
			if block.has_point(Vector2(p.x, p.z)):
				for b: Dictionary in plan["buildings"]:
					if (b["footprint"] as Rect2).has_point(Vector2(p.x, p.z)):
						return false
				return true
		return false
	assert_int((s["corners"] as Array).size()).is_equal(4)
	for c: Dictionary in s["corners"]:
		assert_bool(on_pavement.call(c["at"])).is_true()
	assert_int((s["routes"] as Array).size()).is_equal(2)
	for route: Array in s["routes"]:
		assert_int(route.size()).is_greater_equal(4)
		for p: Vector3 in route:
			assert_bool(on_pavement.call(p)).is_true()


func test_roof_posts_only_on_flat_roofs() -> void:
	var s := _spots()
	for r: Dictionary in s["roofs"]:
		assert_float(float(((r["building"] as Dictionary)["params"] as Dictionary)["roof"])).is_equal(2.0)
