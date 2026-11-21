extends GdUnitTestSuite
## The generated map as the played land (#472): MapShape answers what the terrain and
## scenery ask, and the voxel world streams it from the camp.

const WORLD := "res://modules/world/scenes/world.tscn"


func after() -> void:
	WorldMaps.clear()


func _shape() -> MapShape:
	WorldMaps.select("grassland", 1)
	return WorldMaps.shape()


func test_heights_are_the_shaped_land() -> void:
	var map := _shape()
	var works: Earthworks = map.map["works"]
	for p: Vector2 in [Vector2(0, 0), Vector2(300, -200), Vector2(-700, 650)]:
		assert_float(map.height_at(p.x, p.y)).is_equal(works.height(p.x, p.y))
	assert_float(map.low()).is_less(map.high())


func test_the_highway_leads_away_from_the_camp_and_is_a_road() -> void:
	var map := _shape()
	var camp := map.camp()
	var last := 0.0
	for metres: float in [0.0, 50.0, 200.0, 600.0]:
		var p := map.road_point(metres)
		assert_bool(map.near_road(p.x, p.z, 0.5)).override_failure_message("%.0f m" % metres).is_true()
		var d := Vector2(p.x - camp.x, p.z - camp.z).length()
		if metres > 0.0:
			assert_float(d).is_greater(last - 1.0)
		last = d
	assert_float(map.forward().length()).is_equal_approx(1.0, 0.001)


func test_every_pond_is_a_water_body_with_its_level() -> void:
	var map := _shape()
	var ponds := (map.map["land"] as WorldLand).ponds()
	assert_int(map.water.bodies.size()).is_equal(ponds.size())
	for i in ponds.size():
		var centre: Vector2 = ponds[i]["centre"]
		assert_float(map.water.level_at(centre.x, centre.y)).is_equal(float(ponds[i]["level"]))


func test_the_terrain_streams_from_the_camp() -> void:
	var map := _shape()
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	var voxels: VoxelWorld = world.get_node("Terrain")
	assert_object(voxels.heights).is_same(map)
	assert_vector(voxels.home).is_equal(map.camp())
	assert_bool(voxels.is_ready_at(voxels.home)).is_true()
	world.queue_free()


func test_a_hollow_inside_a_ponds_outline_but_off_the_pond_is_dry() -> void:
	var map := _shape()
	var land: WorldLand = map.map["land"]
	for body: Dictionary in map.water.bodies:
		var box: Rect2 = body["box"]
		for k in 40:
			var p := box.position + box.size * Vector2(fmod(k * 0.618, 1.0), fmod(k * 0.382, 1.0))
			if is_nan(land.water_level(p.x, p.y)):
				assert_bool(is_nan(map.water.level_at(p.x, p.y))).override_failure_message("%s" % p).is_true()


func test_every_road_is_cut_into_pieces_filed_under_its_chunks() -> void:
	var map := _shape()
	var s := SceneryScatter.new()
	s.set(&"_visual", false)
	add_child(s)
	s.set_process(false)
	var lines: Array = s.get(&"_lines")
	var pieces: Dictionary = s.get(&"_line_pieces")
	assert_int(lines.size()).is_equal((map.map["net"] as RoadNetwork).roads().size())
	var total := 0.0
	for chunk: int in pieces:
		for piece: Vector3 in pieces[chunk]:
			var at := (lines[int(piece.x)] as RoadLine).point_at(piece.y)
			assert_int(s.chunk_at(at.x, at.y)).is_equal(chunk)
			total += piece.z * 2.0
	var length := 0.0
	for line: RoadLine in lines:
		length += line.length()
	assert_float(total).is_equal_approx(length, 1.0)
	s.queue_free()


func test_the_city_footprint_is_the_size_the_city_module_builds_and_faces_the_highway() -> void:
	var city_cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://modules/city/data/city.json"))
	for recipe_name in ["grassland", "mixed"]:
		var recipe: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://modules/world/data/maps/%s.json" % recipe_name))
		assert_float(float(recipe["settlements"]["city"]["max_size"])).override_failure_message(recipe_name).is_equal(float(city_cfg["size"]))
	var map := _shape()
	var city := map.city()
	assert_float(float(city["size"])).is_less_equal(float(city_cfg["size"]))
	# The highway's last point lies off the side the city faces.
	var points := map.highway()
	var end := points[points.size() - 1]
	var centre: Vector3 = city["centre"]
	var to_end := Vector3(end.x - centre.x, 0.0, end.y - centre.z).normalized()
	assert_float(to_end.dot(city["toward"])).is_greater(0.7)


func test_sites_of_a_kind_stand_on_their_levelled_pad() -> void:
	var map := _shape()
	var wanted := (map.map["sites"] as MapSites).sites().filter(func(s: Dictionary) -> bool: return s["kind"] == "water_tower")
	var found := map.sites("water_tower")
	assert_int(found.size()).is_equal(wanted.size())
	assert_int(found.size()).is_greater(0)
	for i in found.size():
		var centre: Vector2 = wanted[i]["centre"]
		assert_float(found[i].x).is_equal(centre.x)
		assert_float(found[i].z).is_equal(centre.y)
		assert_float(found[i].y).is_equal_approx(map.height_at(centre.x, centre.y), 0.01)
	assert_array(map.sites("no such kind")).is_empty()


func test_no_tree_or_rock_grows_on_or_beside_a_site_pad() -> void:
	var map := _shape()
	var s := SceneryScatter.new()
	s.set(&"_visual", false)
	add_child(s)
	s.set_process(false)
	var all := (map.map["sites"] as MapSites).sites()
	assert_int(all.size()).is_greater(0)
	var clearance: Dictionary = (Data.load_json("res://modules/world/data/world.json") as Dictionary)["scatter"]["site_clearance"]
	for site: Dictionary in all:
		var foot: Rect2 = site["footprint"]
		assert_bool(map.on_site(foot.get_center().x, foot.get_center().y)).is_true()
		# Nor within the kind's clearance round it, so nothing crowds what stands there.
		var clear := float(clearance.get(site["kind"], clearance["default"]))
		assert_float(clear).is_greater(0.0)
		var area := foot.grow(clear)
		# Every chunk the area reaches into: a farm can straddle a chunk edge.
		var chunks := {}
		for corner: Vector2 in [area.position, area.end, Vector2(area.position.x, area.end.y), Vector2(area.end.x, area.position.y)]:
			chunks[s.chunk_at(corner.x, corner.y)] = true
		for chunk: int in chunks:
			var plan := s.plan_chunk(chunk, [] as Array[Vector3])
			for kind: String in ["trees", "rocks"]:
				for thing: Dictionary in plan[kind]:
					var at: Vector3 = (thing["xform"] as Transform3D).origin
					assert_bool(area.has_point(Vector2(at.x, at.z))).override_failure_message("%s by a %s" % [kind, site["kind"]]).is_false()
	assert_bool(map.on_site(map.camp().x, map.camp().z)).is_false()
	s.queue_free()


func test_a_pad_levels_the_ground_beside_a_road_but_not_the_road() -> void:
	var map := _shape()
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	var voxels: VoxelWorld = world.get_node("Terrain")
	var on_road := map.road_point(150.0)
	var across := (map.road_point(151.0) - on_road).cross(Vector3.UP).normalized()
	# The first spot off to the side that is past the road's edge and its fade.
	var beside := on_road
	for step in 40:
		beside = on_road + across * float(step) * 0.5
		if map.road_edge_distance(beside.x, beside.z) > voxels.PAD_ROAD_GAP + 0.5:
			break
	var level := maxf(on_road.y, voxels.ground_height(beside.x, beside.z)) + 4.0
	voxels.set_pads_for(&"test_pad", [{"at": Vector3(on_road.x, level, on_road.z), "half": Vector2(30.0, 30.0), "yaw": 0.0, "blend": 3.0}])
	assert_float(voxels.surface_height(on_road.x, on_road.z)).is_equal_approx(voxels.ground_height(on_road.x, on_road.z), 0.01)
	assert_float(voxels.surface_height(beside.x, beside.z)).is_equal_approx(level, 0.01)
	voxels.set_pads_for(&"test_pad", [])
	world.queue_free()


func test_a_map_name_that_is_not_a_recipe_plays_the_default() -> void:
	var cfg: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string("res://modules/world/data/world.json")) as Dictionary)["map"]
	var module: GDScript = load("res://modules/world/world_module.gd")
	Log.begin_capture()
	var picked: bool = module.call(&"_select_map", PackedStringArray(["--map=no_such_recipe", "--seed=3"]), cfg)
	Log.end_capture()
	assert_bool(picked).is_true()
	assert_str(WorldMaps.recipe_name()).is_equal(str(cfg["recipe"]))
	assert_int(WorldMaps.seed_value()).is_equal(3)
	WorldMaps.clear()
