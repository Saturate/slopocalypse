extends GdUnitTestSuite
## The harbour by the camp (#454): on every island seed the jetty starts where the ground
## meets its deck and runs out over water deep enough for a boat; the shed and props stand on
## dry land clear of the jetty and of each other, the boat floats beside it; and on the
## default map the deck is solid and level from the shore end to the sea end, and a player
## walks up onto it from the beach and out along it.

const MODULE := "res://modules/harbour/harbour_module.gd"
const PLAYER := "res://modules/player/scenes/player.tscn"
const RECIPES := ["res://modules/world/data/maps/grassland.json", "res://modules/world/data/maps/mixed.json"]
const SEEDS := 6


## Stands in for the voxel world: the map's ground height, nothing else.
class Ground:
	extends Node
	var shape: MapShape

	func ground_height(x: float, z: float) -> float:
		return shape.height_at(x, z)


func after() -> void:
	WorldMaps.clear()


func _cfg() -> Dictionary:
	return Data.load_json(HarbourPlan.CONFIG)


## The harbour as MapShape.harbour gives it, from the settlements alone (no roads built).
func _harbour(s: Settlements) -> Dictionary:
	var h := s.harbour()
	if h.is_empty():
		return {}
	var f: Vector2 = h["facing"]
	return {"root": h["root"], "facing": Vector3(f.x, 0.0, f.y), "length": h["length"], "end": h["end"], "depth": h["depth"], "footprint": h["footprint"]}


## A piece's footprint as a rectangle in the jetty's frame (x across, z out to sea from its
## shore end).
func _in_frame(piece: Dictionary, start: Vector3, facing: Vector3) -> Rect2:
	var foot := HarbourPlan.footprint(str(piece["generator"]), piece["params"])
	var t: Transform3D = piece["transform"]
	var right := facing.cross(Vector3.UP)
	var out := Rect2()
	var first := true
	for c: Vector2 in [foot.position, Vector2(foot.end.x, foot.position.y), foot.end, Vector2(foot.position.x, foot.end.y)]:
		var d := t * Vector3(c.x, 0.0, c.y) - start
		var p := Vector2(d.dot(right), d.dot(facing))
		out = Rect2(p, Vector2.ZERO) if first else out.expand(p)
		first = false
	return out


func test_on_every_seed_the_jetty_runs_from_the_shore_into_deep_water_with_its_pieces_beside_it() -> void:
	var cfg := _cfg()
	var jetty_cfg: Dictionary = cfg["jetty"]
	var width := float(jetty_cfg["params"]["width"])
	for path: String in RECIPES:
		var recipe: Dictionary = Data.load_json(path)
		var min_depth := float(recipe["settlements"]["harbour"]["min_depth"])
		for seed_value in SEEDS:
			var where := "%s seed %d" % [path.get_file(), seed_value]
			var land := WorldLand.new(recipe, seed_value)
			var s := Settlements.new(LandZones.new(land, recipe["zones"]), recipe["settlements"])
			var harbour := _harbour(s)
			if harbour.is_empty():
				continue
			var ground := func(x: float, z: float) -> float: return land.height(x, z)
			var line := HarbourPlan.jetty_line(harbour, ground, cfg)
			var start: Vector3 = line["start"]
			var facing: Vector3 = line["facing"]
			var deck := float(line["deck"])
			var length := float(line["length"])
			var sea := land.sea_level
			# The shore it starts from is a beach, not grass down to the water.
			var root: Vector3 = harbour["root"]
			assert_float(land.sand(root.x - facing.x, root.z - facing.z)).override_failure_message(where + ": no sand at the jetty's foot").is_greater(0.5)
			assert_bool(line["landed"]).override_failure_message(where + ": the ground never meets the deck").is_true()
			# Walked straight onto from the shore: the ground there no more than a step under it.
			var at_start := land.height(start.x, start.z)
			assert_float(deck - at_start).override_failure_message(where + ": %.2f m up onto the deck" % (deck - at_start)).is_between(0.0, float(jetty_cfg["step"]))
			assert_float(deck - sea).is_equal_approx(float(jetty_cfg["freeboard"]), 0.001)
			# Never buried along its way out, and deep water at its end for the boat.
			var k := 0.5
			while k <= length:
				var p := start + facing * k
				assert_float(land.height(p.x, p.z)).override_failure_message("%s: ground over the deck %.1f m out" % [where, k]).is_less_equal(deck)
				k += 0.5
			var end := start + facing * length
			assert_float(sea - land.height(end.x, end.z)).override_failure_message(where + ": shallow at the jetty's end").is_greater_equal(min_depth)
			assert_float(length).is_less_equal(float(jetty_cfg["landing"]) + float(recipe["settlements"]["harbour"]["length"][1]) + VoxJetty.SECTION)
			var pieces := HarbourPlan.plan(harbour, ground, cfg)
			var jetty := pieces.filter(func(p: Dictionary) -> bool: return p["kind"] == "jetty")
			# End to end from the shore end, each piece's deck at the same height, the whole length.
			var along := 0.0
			for piece: Dictionary in jetty:
				var t: Transform3D = piece["transform"]
				var half := VoxJetty.length(piece["params"]) / 2.0
				var near_end := t * Vector3(0.0, VoxJetty.deck_top(piece["params"]), -half)
				assert_float(Vector2(near_end.x - start.x, near_end.z - start.z).length()).override_failure_message(where + ": a gap in the jetty").is_equal_approx(along, 0.01)
				assert_float(near_end.y).is_equal_approx(deck, 0.001)
				along += half * 2.0
				# The piles reach the ground under it, so it does not hang over the water.
				var far_end := t * Vector3(0.0, 0.0, half)
				assert_float(t.origin.y).override_failure_message(where + ": piles short of the sea bed").is_less_equal(land.height(far_end.x, far_end.z) + 0.05)
			assert_float(along).is_equal_approx(length, 0.01)
			# Only the last piece has the ladder, at the sea end.
			for n in jetty.size():
				assert_float(float(jetty[n]["params"]["ladder"])).is_equal(1.0 if n == jetty.size() - 1 else 0.0)
			# Every piece put up, all on the ground set aside for the harbour (roads, sites, power
			# and trees keep off it).
			assert_int(pieces.size() - jetty.size()).override_failure_message(where + ": a piece left out").is_equal((cfg["pieces"] as Array).size())
			var reserved: Rect2 = harbour["footprint"]
			for piece: Dictionary in pieces:
				var t: Transform3D = piece["transform"]
				var foot := HarbourPlan.footprint(str(piece["generator"]), piece["params"])
				for c: Vector2 in [foot.position, Vector2(foot.end.x, foot.position.y), foot.end, Vector2(foot.position.x, foot.end.y)]:
					var p := t * Vector3(c.x, 0.0, c.y)
					# The jetty's far end and the boat may reach out past it over open sea, where
					# nothing is placed.
					if land.is_sea(p.x, p.z):
						continue
					assert_bool(reserved.has_point(Vector2(p.x, p.z))).override_failure_message("%s: %s outside the harbour's ground" % [where, piece["kind"]]).is_true()
			var deck_rect := Rect2(-width / 2.0, 0.0, width, length)
			var rects: Array[Rect2] = []
			for i in range(jetty.size(), pieces.size()):
				var piece := pieces[i]
				var name := "%s: %s" % [where, piece["kind"]]
				var rect := _in_frame(piece, Vector3(start.x, 0.0, start.z), facing)
				assert_bool(rect.intersects(deck_rect)).override_failure_message(name + " on the jetty").is_false()
				for other in rects:
					assert_bool(rect.intersects(other)).override_failure_message(name + " in another piece").is_false()
				rects.append(rect)
				var t: Transform3D = piece["transform"]
				var foot := HarbourPlan.footprint(str(piece["generator"]), piece["params"])
				for c: Vector2 in [foot.position, Vector2(foot.end.x, foot.position.y), foot.end, Vector2(foot.position.x, foot.end.y)]:
					var p := t * Vector3(c.x, 0.0, c.y)
					if piece["generator"] == "VoxBoat":
						assert_float(land.height(p.x, p.z)).override_failure_message(name + " aground").is_less(sea - VoxBoat.WATERLINE)
					else:
						assert_float(land.height(p.x, p.z)).override_failure_message(name + " in the water").is_greater(sea)
						# Set into the ground, never standing over it.
						assert_float(t.origin.y).is_less_equal(land.height(p.x, p.z))
				if piece["generator"] == "VoxBoat":
					assert_float(t.origin.y).is_equal_approx(sea - VoxBoat.WATERLINE, 0.001)


func test_nothing_without_a_harbour() -> void:
	assert_array(HarbourPlan.plan({}, func(_x: float, _z: float) -> float: return 0.0, _cfg())).is_empty()
	assert_array(HarbourPlan.check(_cfg())).is_empty()


func test_the_deck_is_solid_and_level_from_the_shore_to_the_sea_end() -> void:
	WorldMaps.clear()
	assert_bool(WorldMaps.select_default()).is_true()
	var shape := WorldMaps.shape()
	assert_bool(shape.harbour().is_empty()).override_failure_message("the default map has no harbour").is_false()
	var ground: Ground = auto_free(Ground.new())
	ground.shape = shape
	ground.add_to_group(&"ground")
	add_child(ground)
	var module: Node = auto_free((load(MODULE) as GDScript).new())
	add_child(module)
	EventBus.publish(&"world.ready", {"harbour": shape.harbour()})
	var pieces: Array = module.get(&"pieces")
	var planned := HarbourPlan.plan(shape.harbour(), Callable(ground, &"ground_height"), _cfg())
	assert_int(pieces.size()).is_equal(planned.size())
	# Built once, however often the world says it is ready.
	EventBus.publish(&"world.ready", {"harbour": shape.harbour()})
	assert_int((module.get(&"pieces") as Array).size()).is_equal(planned.size())
	await get_tree().physics_frame
	await get_tree().physics_frame
	var line := HarbourPlan.jetty_line(shape.harbour(), Callable(ground, &"ground_height"), _cfg())
	var start: Vector3 = line["start"]
	var facing: Vector3 = line["facing"]
	var deck := float(line["deck"])
	var right := facing.cross(Vector3.UP)
	var width := float(_cfg()["jetty"]["params"]["width"])
	var space := (module.get_child(0) as Node3D).get_world_3d().direct_space_state
	var k := 0.3
	while k < float(line["length"]):
		# Across the walkway inside the kerbs, not only down its middle.
		for x: float in [-width / 4.0, 0.0, width / 4.0]:
			var p := start + facing * k + right * x
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x, deck + 3.0, p.z), Vector3(p.x, deck - 3.0, p.z)))
			assert_bool(hit.is_empty()).override_failure_message("nothing under %.1f m out" % k).is_false()
			if not hit.is_empty():
				assert_float((hit["position"] as Vector3).y).override_failure_message("deck at %.1f m out" % k).is_equal_approx(deck, 0.02)
		k += 0.7


func test_a_player_walks_from_the_beach_onto_the_jetty_and_out_along_it() -> void:
	if not ResourceLoader.exists(PLAYER):
		return
	WorldMaps.clear()
	assert_bool(WorldMaps.select_default()).is_true()
	var shape := WorldMaps.shape()
	var ground: Ground = auto_free(Ground.new())
	ground.shape = shape
	ground.add_to_group(&"ground")
	add_child(ground)
	var line := HarbourPlan.jetty_line(shape.harbour(), Callable(ground, &"ground_height"), _cfg())
	var start: Vector3 = line["start"]
	var facing: Vector3 = line["facing"]
	var deck := float(line["deck"])
	# The beach round the shore end as the physics sees it: heights a metre apart.
	var side := 41
	var heights := PackedFloat32Array()
	for j in side:
		for i in side:
			heights.append(shape.height_at(start.x + i - side / 2, start.z + j - side / 2))
	var beach: StaticBody3D = auto_free(StaticBody3D.new())
	var collider := CollisionShape3D.new()
	var map := HeightMapShape3D.new()
	map.map_width = side
	map.map_depth = side
	map.map_data = heights
	collider.shape = map
	beach.add_child(collider)
	add_child(beach)
	beach.global_position = Vector3(roundf(start.x), 0.0, roundf(start.z))
	var module: Node = auto_free((load(MODULE) as GDScript).new())
	add_child(module)
	EventBus.publish(&"world.ready", {"harbour": shape.harbour()})
	var player: PlayerController = auto_free((load(PLAYER) as PackedScene).instantiate())
	add_child(player)
	var from := start - facing * 4.0
	player.global_position = Vector3(from.x, shape.height_at(from.x, from.z) + 0.1, from.z)
	# Facing out to sea (a body looks down its -z).
	player.rotation.y = atan2(-facing.x, -facing.z)
	player.intent().move = Vector2(0, 1)
	for i in 240:
		await get_tree().physics_frame
	player.intent().move = Vector2.ZERO
	for i in 20:
		await get_tree().physics_frame
	var out := (player.global_position - start).dot(facing)
	assert_float(out).override_failure_message("stopped %.1f m from the shore end" % out).is_greater(8.0)
	assert_float(player.global_position.y).is_equal_approx(deck, 0.1)
