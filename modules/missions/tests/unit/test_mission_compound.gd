extends GdUnitTestSuite
## A mission at a map site reads as one guarded place: its buildings hug the site's pad
## instead of standing in a wide ring, and a fence runs round the lot with a gate where the
## site's track leaves, kept off roads, and the same on every machine.

const CONFIG := "res://modules/missions/data/missions.json"
## A farm-sized pad round the origin, its track leaving north (-z).
const FOOT := Rect2(-22.0, -16.0, 44.0, 32.0)


func _config() -> Dictionary:
	return Data.load_json(CONFIG)


func _place() -> Dictionary:
	return {"centre": Vector3(0.0, 12.0, 0.0), "footprint": FOOT, "toward": Vector3.FORWARD}


func _buildings(cfg: Dictionary, seed_value: int, blocked := Callable()) -> Array:
	return MissionLayout.buildings(cfg["buildings"], seed_value, _place(), blocked)


## How far `at` lies from the nearest point of `foot`.
static func _off(foot: Rect2, at: Vector3) -> float:
	var nearest := Vector2(clampf(at.x, foot.position.x, foot.end.x), clampf(at.z, foot.position.y, foot.end.y))
	return nearest.distance_to(Vector2(at.x, at.z))


func test_buildings_stand_close_round_the_sites_pad() -> void:
	var cfg := _config()
	var off: Array = cfg["buildings"]["off_site"]
	for seed_value in 20:
		var out := _buildings(cfg, seed_value)
		assert_int(out.size()).is_greater(1)
		for entry: Dictionary in out:
			var at: Vector3 = entry["position"]
			var r := float(entry["radius"])
			# Off the pad, and no further out than the layout's offset allows.
			assert_float(_off(FOOT, at) - r).is_greater_equal(float(off[0]) - 0.01)
			assert_bool(FOOT.grow(float(off[1]) + r + 0.01).has_point(Vector2(at.x, at.z))).override_failure_message("seed %d: a building at %s, too far off the pad" % [seed_value, at]).is_true()


func test_the_fence_rings_every_building_with_room_round_it() -> void:
	var cfg := _config()
	for seed_value in 10:
		var out := _buildings(cfg, seed_value)
		var runs := MissionLayout.fence(cfg["compound"], _place(), out, seed_value)
		assert_int(runs.size()).is_greater(8)
		var ring := _ring(runs)
		for entry: Dictionary in out:
			var at: Vector3 = entry["position"]
			assert_bool(ring.grow(-float(entry["radius"])).has_point(Vector2(at.x, at.z))).is_true()
		assert_bool(ring.encloses(FOOT)).is_true()


func test_the_fence_leaves_a_gate_where_the_track_leaves() -> void:
	var cfg := _config()
	var gate := float(cfg["compound"]["gate"])
	var runs := MissionLayout.fence(cfg["compound"], _place(), _buildings(cfg, 3), 3)
	var ring := _ring(runs)
	# The track leaves north along x = 0: no run of the north side comes within half the gate
	# of it, while the south side is whole there.
	var north := runs.filter(func(r: Dictionary) -> bool: return absf((r["from"] as Vector3).z - ring.position.y) < 0.01 and absf((r["to"] as Vector3).z - ring.position.y) < 0.01)
	assert_int(north.size()).is_greater(0)
	for r: Dictionary in north:
		var a := minf((r["from"] as Vector3).x, (r["to"] as Vector3).x)
		var b := maxf((r["from"] as Vector3).x, (r["to"] as Vector3).x)
		assert_bool(b <= -gate / 2.0 + 0.01 or a >= gate / 2.0 - 0.01).override_failure_message("a run across the gate, %.1f to %.1f" % [a, b]).is_true()
	var south := runs.filter(func(r: Dictionary) -> bool: return absf((r["from"] as Vector3).z - ring.end.y) < 0.01 and minf((r["from"] as Vector3).x, (r["to"] as Vector3).x) <= 0.0 and maxf((r["from"] as Vector3).x, (r["to"] as Vector3).x) >= 0.0)
	assert_int(south.size()).is_greater(0)


func test_no_fence_run_stands_where_it_is_blocked() -> void:
	var cfg := _config()
	# A road running north along x = 30 m, where the fence's east side would run.
	var road := func(at: Vector3, radius: float) -> bool: return absf(at.x - 30.0) < radius + 3.0
	var runs := MissionLayout.fence(cfg["compound"], _place(), _buildings(cfg, 5), 5, road)
	assert_int(runs.size()).is_greater(4)
	for r: Dictionary in runs:
		var mid := ((r["from"] as Vector3) + (r["to"] as Vector3)) / 2.0
		var half := (r["from"] as Vector3).distance_to(r["to"]) / 2.0
		assert_bool(bool(road.call(mid, half))).is_false()


func test_runs_come_in_two_lengths_so_their_meshes_are_shared() -> void:
	var cfg := _config()
	var step := float(cfg["compound"]["segment"])
	var lengths := {}
	for r: Dictionary in MissionLayout.fence(cfg["compound"], _place(), _buildings(cfg, 8), 8):
		var length := (r["from"] as Vector3).distance_to(r["to"])
		assert_float(length).is_less_equal(step + 0.001)
		lengths[snappedf(length, 0.001)] = true
	assert_int(lengths.size()).is_less_equal(2)


func test_the_same_place_gives_the_same_fence() -> void:
	var cfg := _config()
	var out := _buildings(cfg, 4)
	assert_array(MissionLayout.fence(cfg["compound"], _place(), out, 4)).is_equal(MissionLayout.fence(cfg["compound"], _place(), out, 4))


func test_a_roadside_spot_gets_no_fence() -> void:
	var cfg := _config()
	var place := {"centre": Vector3.ZERO, "footprint": Rect2(Vector2.ZERO, Vector2.ZERO), "toward": Vector3.FORWARD}
	var out := MissionLayout.buildings(cfg["buildings"], 1, place)
	assert_array(MissionLayout.fence(cfg["compound"], place, out, 1)).is_empty()


## The rectangle the runs go round.
static func _ring(runs: Array) -> Rect2:
	var a: Vector3 = (runs[0] as Dictionary)["from"]
	var rect := Rect2(Vector2(a.x, a.z), Vector2.ZERO)
	for r: Dictionary in runs:
		for p: Vector3 in [r["from"], r["to"]]:
			rect = rect.expand(Vector2(p.x, p.z))
	return rect
