extends GdUnitTestSuite
## What the camp is built of (#420): a fence along every run of the layout with its planks
## facing out, no two posts in each other at the corners, the hut on its spot, and yards on
## the pad clear of the hut and of each other.

const WAYS: Array[Vector3] = [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]


func _camp(way: Vector3) -> CampLayout:
	var cfg: Dictionary = (Data.load_json(CampLayout.CONFIG) as Dictionary)["camp"]
	var side := float((Data.load_json("res://modules/world/data/maps/grassland.json") as Dictionary)["settlements"]["camp"]["size"])
	var centre := Vector3(100.0, 20.0, -50.0)
	return CampLayout.make(centre, way, Rect2(Vector2(centre.x, centre.z) - Vector2.ONE * side / 2.0, Vector2.ONE * side), cfg)


func _cfg() -> Dictionary:
	return Data.load_json(CampPlan.CONFIG)


func test_a_fence_on_every_run_planks_out_and_a_hut() -> void:
	for way in WAYS:
		var camp := _camp(way)
		var pieces := CampPlan.plan(camp, _cfg())
		var fences := pieces.filter(func(p: Dictionary) -> bool: return p["kind"] == "fence")
		var huts := pieces.filter(func(p: Dictionary) -> bool: return p["kind"] == "hut")
		assert_int(fences.size()).is_equal(camp.fence_runs().size())
		assert_int(huts.size()).is_equal(1)
		for f: Dictionary in fences:
			var t: Transform3D = f["transform"]
			var half := float(f["params"]["length"]) / 2.0
			# Both ends on the fence line, inside the pad, and +z (away from the planks) inward.
			for x: float in [-half, half]:
				var end := t * Vector3(x, 0.0, 0.0)
				assert_float(camp.distance(end)).is_less(0.01)
				assert_bool(camp.inside(end, 0.5)).is_false()
				assert_bool(camp.pad.has_point(Vector2(end.x, end.z))).is_true()
			var inward := Vector3(camp.centre.x - t.origin.x, 0.0, camp.centre.z - t.origin.z)
			assert_float(t.basis.z.dot(inward)).is_greater(0.0)
			assert_float(t.basis.x.dot(Vector3.UP)).is_equal_approx(0.0, 0.001)
		var hut: Dictionary = huts[0]
		assert_bool((hut["transform"] as Transform3D).origin.is_equal_approx(camp.spot("hut").origin + Vector3.DOWN * float(_cfg()["sink"]))).is_true()
		assert_float(float(hut["params"]["width"])).is_equal(camp.hut_size.x)


func test_only_the_back_and_gate_runs_have_tall_corner_posts() -> void:
	var camp := _camp(Vector3.FORWARD)
	var pieces := CampPlan.plan(camp, _cfg())
	# Every corner has exactly one tall post: the sides stop short of them.
	var tall_ends: Array[Vector3] = []
	for p: Dictionary in pieces:
		if p["kind"] != "fence" or int(p["params"]["tall_ends"]) == 0:
			continue
		var t: Transform3D = p["transform"]
		var half := float(p["params"]["length"]) / 2.0
		tall_ends.append(t * Vector3(-half, 0.0, 0.0))
		tall_ends.append(t * Vector3(half, 0.0, 0.0))
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var at := camp.point(corner * camp.half)
		var near := tall_ends.filter(func(e: Vector3) -> bool: return e.distance_to(at) < 0.1)
		assert_int(near.size()).override_failure_message("corner %s" % corner).is_equal(1)
	for p: Dictionary in pieces:
		if p["kind"] == "fence" and int(p["params"]["tall_ends"]) == 0:
			var t: Transform3D = p["transform"]
			var half := float(p["params"]["length"]) / 2.0
			for x: float in [-half, half]:
				for e in tall_ends:
					assert_float((t * Vector3(x, 0.0, 0.0)).distance_to(e)).is_greater_equal(VoxFence.END_POST - 0.001)


func test_the_yards_are_on_the_pad_and_clear_of_the_hut() -> void:
	for way in WAYS:
		var camp := _camp(way)
		var yards := CampPlan.yards(camp, _cfg())
		assert_int(yards.size()).is_equal((_cfg()["yard"] as Array).size())
		var hut := camp.spot("hut")
		var floor := Rect2()
		for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var p := hut * Vector3(corner.x * camp.hut_size.x / 2.0, 0.0, corner.y * camp.hut_size.y / 2.0)
			floor = Rect2(Vector2(p.x, p.z), Vector2.ZERO) if floor.size == Vector2.ZERO and floor.position == Vector2.ZERO else floor.expand(Vector2(p.x, p.z))
		for i in yards.size():
			var rect: Rect2 = yards[i]["rect"]
			assert_bool(camp.pad.grow(0.01).encloses(rect)).is_true()
			assert_bool(rect.intersects(floor.grow(0.49))).override_failure_message("a yard under the hut").is_false()
			assert_float(float(yards[i]["level"])).is_equal(camp.centre.y)
			for j in range(i + 1, yards.size()):
				assert_float(rect.intersection(yards[j]["rect"]).get_area()).is_equal_approx(0.0, 0.001)
		# The lane reaches the pad's edge where the highway starts.
		var lane: Rect2 = yards[0]["rect"]
		var edge := camp.point(Vector2(0.0, camp.pad.size.x / 2.0))
		assert_bool(lane.grow(0.01).has_point(Vector2(edge.x, edge.z))).is_true()
