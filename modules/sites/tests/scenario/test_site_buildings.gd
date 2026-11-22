extends GdUnitTestSuite
## On the default map every farm, cabin, antenna and lookout site gets its buildings, at the
## same places on two builds of the map from the same seed; they are solid, and the lookout
## tower's ladder takes a player up to its deck.

const MODULE := "res://modules/sites/sites_module.gd"
const PLAYER := "res://modules/player/scenes/player.tscn"
const BUILT := ["farm", "cabin", "antenna", "lookout"]


## Stands in for the voxel world: the map's sites, nothing else.
class Ground:
	extends Node
	var shape: MapShape

	func map_site_list() -> Array[Dictionary]:
		return shape.site_list()


func after() -> void:
	WorldMaps.clear()


func _default_shape() -> MapShape:
	WorldMaps.clear()
	assert_bool(WorldMaps.select_default()).is_true()
	return WorldMaps.shape()


func _config() -> Dictionary:
	return Data.load_json(SiteLayout.CONFIG)


func test_every_built_kind_gets_its_pieces_alike_on_two_builds() -> void:
	var cfg := _config()
	var sites := _default_shape().site_list()
	var first := SiteLayout.plan(sites, cfg)
	var again := SiteLayout.plan(_default_shape().site_list(), cfg)
	assert_int(again.size()).is_equal(first.size())
	for i in first.size():
		assert_bool((first[i]["transform"] as Transform3D).is_equal_approx(again[i]["transform"])).override_failure_message("piece %d moved" % i).is_true()
		assert_dict(again[i]["params"]).is_equal(first[i]["params"])
	var seen: Dictionary[String, int] = {}
	for i in sites.size():
		var kind := str(sites[i]["kind"])
		if not BUILT.has(kind):
			continue
		seen[kind] = seen.get(kind, 0) + 1
		var wanted := ((cfg["kinds"] as Dictionary)[kind]["pieces"] as Array).size()
		var got := first.filter(func(p: Dictionary) -> bool: return int(p["site"]) == i)
		assert_int(got.size()).override_failure_message("%s site %d" % [kind, i]).is_equal(wanted)
		var centre: Vector3 = sites[i]["centre"]
		var foot: Rect2 = sites[i]["footprint"]
		for p: Dictionary in got:
			var at := (p["transform"] as Transform3D).origin
			# On the pad, inside the footprint.
			assert_bool(foot.has_point(Vector2(at.x, at.z))).is_true()
			assert_float(at.y).is_equal_approx(centre.y - float(cfg["sink"]), 0.001)
	for kind: String in BUILT:
		assert_int(seen.get(kind, 0)).override_failure_message("the default map has no %s" % kind).is_greater(0)


func _ground() -> Ground:
	var ground: Ground = auto_free(Ground.new())
	ground.shape = _default_shape()
	ground.add_to_group(&"ground")
	add_child(ground)
	return ground


func test_a_server_builds_them_all_solid_on_world_ready() -> void:
	var ground := _ground()
	var ladders_before := Ladders.count()
	var module: Node = auto_free((load(MODULE) as GDScript).new())
	module.set(&"all_at_once", true)
	add_child(module)
	EventBus.publish(&"world.ready", {})
	var pieces: Array = module.get(&"pieces")
	assert_int(pieces.size()).is_equal(SiteLayout.plan(ground.shape.site_list(), _config()).size())
	var lookouts := 0
	for piece: VoxPiece in pieces:
		assert_int(piece.shape_count()).override_failure_message(piece.name).is_greater(0)
		# Nothing drawn headless, so no voxels kept.
		assert_object(piece.model).is_null()
		if piece.get_meta(&"site_kind") == "lookout":
			lookouts += 1
	assert_int(lookouts).is_greater(0)
	assert_int(Ladders.count() - ladders_before).is_equal(lookouts)
	# Only once, however often the world says it is ready.
	EventBus.publish(&"world.ready", {})
	assert_int((module.get(&"pieces") as Array).size()).is_equal(pieces.size())
	ground.remove_from_group(&"ground")
	module.free()
	assert_int(Ladders.count()).is_equal(ladders_before)


func test_a_client_builds_them_a_few_a_frame_nearest_first() -> void:
	var ground := _ground()
	var cfg := _config()
	var planned := SiteLayout.plan(ground.shape.site_list(), cfg)
	var module: Node = auto_free((load(MODULE) as GDScript).new())
	module.set(&"all_at_once", false)
	add_child(module)
	var from: Vector3 = (planned[planned.size() - 1]["transform"] as Transform3D).origin
	EventBus.publish(&"world.ready", {"spawn": from})
	assert_int((module.get(&"pieces") as Array).size()).is_equal(0)
	await get_tree().process_frame
	await get_tree().process_frame
	var pieces: Array = module.get(&"pieces")
	assert_int(pieces.size()).is_between(1, int(cfg["builds_per_frame"]) * 2)
	# The first one up is the one nearest where the player is.
	var first := (pieces[0] as VoxPiece).global_position
	for p: Dictionary in planned:
		assert_float(from.distance_to(first)).is_less_equal(from.distance_to((p["transform"] as Transform3D).origin) + 0.01)
	for i in planned.size() + 5:
		await get_tree().process_frame
	assert_int((module.get(&"pieces") as Array).size()).is_equal(planned.size())
	ground.remove_from_group(&"ground")


func test_a_player_climbs_the_lookout_ladder_onto_the_deck() -> void:
	if not ResourceLoader.exists(PLAYER):
		return
	var floor_body: StaticBody3D = auto_free(StaticBody3D.new())
	var floor_shape := CollisionShape3D.new()
	var slab := BoxShape3D.new()
	slab.size = Vector3(40, 1, 40)
	floor_shape.shape = slab
	floor_shape.position = Vector3(0, -0.5, 0)
	floor_body.add_child(floor_shape)
	add_child(floor_body)
	var params := {"height": 7.0, "width": 3.0, "roof": 1}
	var tower: VoxPiece = auto_free(VoxPiece.new())
	tower.generator = "VoxLookoutTower"
	tower.params = params
	add_child(tower)
	var climb := VoxLookoutTower.ladder_box(params)
	var player: PlayerController = auto_free((load(PLAYER) as PackedScene).instantiate())
	add_child(player)
	# At the foot of the ladder (on the tower's -z side), facing it.
	player.rotation.y = PI
	player.global_position = Vector3(0.0, 0.05, climb.position.z + 0.4)
	player.intent().move = Vector2(0, 1)
	for i in 300:
		await get_tree().physics_frame
	player.intent().move = Vector2.ZERO
	for i in 30:
		await get_tree().physics_frame
	var deck := VoxLookoutTower.deck_half(3.0)
	assert_float(player.global_position.y).is_equal_approx(7.0, 0.2)
	assert_float(player.global_position.z).is_greater(-deck)
	assert_float(player.global_position.z).is_less(deck)
	# Stepped off onto the deck: no longer holding on to the ladder.
	assert_bool(player.climbing).is_false()


## What a piece stands on (x, z), from its generator's width and depth, or a square of its
## width; a zero rect for pieces without one.
func _piece_box(p: Dictionary) -> Rect2:
	var params: Dictionary = p["params"]
	if not params.has("width"):
		return Rect2()
	var half := Vector3(float(params["width"]), 0.0, float(params.get("depth", params["width"]))) / 2.0
	var xform: Transform3D = p["transform"]
	var box := Rect2(Vector2(xform.origin.x, xform.origin.z), Vector2.ZERO)
	for corner: Vector3 in [Vector3(-half.x, 0, -half.z), Vector3(half.x, 0, -half.z), Vector3(half.x, 0, half.z), Vector3(-half.x, 0, half.z)]:
		var at := xform * corner
		box = box.expand(Vector2(at.x, at.z))
	return box


## Each farm, cabin and lookout's yard (packed dirt painted into the ground) starts where
## its track arrives, reaches every building on it and runs under none of them (#470).
func test_a_sites_yard_joins_its_track_to_its_buildings_without_running_under_them() -> void:
	var shape := _default_shape()
	var sites := shape.site_list()
	var cfg := _config()
	var planned := SiteLayout.plan(sites, cfg)
	var yards := SiteLayout.yards(sites, cfg)
	var starts: Dictionary[String, Vector2] = {}
	for road: Dictionary in (shape.map["net"] as RoadNetwork).roads():
		if road["kind"] == "track":
			starts[str(road["from"])] = (road["points"] as PackedVector2Array)[0]
	var checked := 0
	for i in sites.size():
		var kind := str(sites[i]["kind"])
		if not ["farm", "cabin", "lookout"].has(kind) or not starts.has("%s %d" % [kind, i]):
			continue
		checked += 1
		var mine: Array[Rect2] = []
		for y: Dictionary in yards:
			if int(y["site"]) == i:
				mine.append(y["rect"])
				assert_bool((sites[i]["footprint"] as Rect2).grow(0.01).encloses(y["rect"])).override_failure_message("%s %d: a yard leaves the pad" % [kind, i]).is_true()
		# Two yards over each other would flicker.
		for a in mine.size():
			for b in range(a + 1, mine.size()):
				assert_bool(mine[a].intersects(mine[b])).override_failure_message("%s %d: yards overlap" % [kind, i]).is_false()
		var start := starts["%s %d" % [kind, i]]
		assert_bool(mine.any(func(r: Rect2) -> bool: return r.grow(0.5).has_point(start))).override_failure_message("%s %d: no yard where the track arrives" % [kind, i]).is_true()
		for p: Dictionary in planned:
			var box := _piece_box(p)
			if int(p["site"]) != i or box.size == Vector2.ZERO:
				continue
			var what := "%s %d: %s" % [kind, i, p["generator"]]
			assert_bool(mine.any(func(r: Rect2) -> bool: return r.grow(1.0).intersects(box))).override_failure_message(what + " is out of the yard's reach").is_true()
			assert_bool(mine.any(func(r: Rect2) -> bool: return r.intersects(box.grow(-0.5)))).override_failure_message(what + " stands on the yard").is_false()
	assert_int(checked).is_greater(2)
