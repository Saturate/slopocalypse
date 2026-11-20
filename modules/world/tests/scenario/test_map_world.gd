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
