extends GdUnitTestSuite
## The map builds on a worker thread (#515): frames keep coming while it builds, and the
## result is the same map a build on the main thread makes.

const RECIPE := "grassland"
const SEED := 1
## Height samples a side for the fingerprint.
const GRID := 48


func after_test() -> void:
	WorldMaps.clear()


## A digest of everything placing systems read: road and track points, site footprints, the
## camp and a grid of heights over the map.
static func fingerprint(map: MapShape) -> String:
	var parts: Array = []
	var net: RoadNetwork = map.map["net"]
	for road in net.roads():
		parts.append(road["points"])
	var sites: MapSites = map.map["sites"]
	for site in sites.sites():
		parts.append(site["footprint"])
	parts.append(map.camp())
	var heights := PackedFloat64Array()
	var area := map.extent()
	for j in GRID:
		for i in GRID:
			heights.append(map.height_at(area.position.x + (i + 0.5) * area.size.x / GRID, area.position.y + (j + 0.5) * area.size.y / GRID))
	parts.append(heights)
	parts.append([map.low(), map.high()])
	return var_to_bytes(parts).hex_encode().sha256_text()


func test_a_threaded_build_lets_frames_run_and_matches_the_main_thread_build() -> void:
	WorldMaps.select(RECIPE, SEED)
	var on_main := fingerprint(WorldMaps.shape())
	WorldMaps.clear()
	WorldMaps.select(RECIPE, SEED)
	assert_bool(WorldMaps.start_build()).is_true()
	var frames := 0
	while WorldMaps.is_building():
		frames += 1
		await get_tree().process_frame
	# The build takes over a second; frames ran all through it.
	assert_int(frames).is_greater(5)
	var map := WorldMaps.shape()
	assert_object(map).is_not_null()
	assert_str(fingerprint(map)).is_equal(on_main)


func test_shape_waits_for_a_running_build() -> void:
	WorldMaps.select(RECIPE, SEED)
	assert_bool(WorldMaps.start_build()).is_true()
	var map := WorldMaps.shape()
	assert_object(map).is_not_null()
	assert_bool(WorldMaps.is_building()).is_false()
	# Built once: asking again is the same map, not a second build.
	assert_object(WorldMaps.shape()).is_same(map)


func test_selecting_another_map_drops_the_running_build() -> void:
	WorldMaps.select(RECIPE, SEED)
	WorldMaps.start_build()
	WorldMaps.select(RECIPE, SEED + 1)
	assert_bool(WorldMaps.is_building()).is_false()
	var other := WorldMaps.shape()
	WorldMaps.clear()
	WorldMaps.select(RECIPE, SEED + 1)
	assert_str(fingerprint(other)).is_equal(fingerprint(WorldMaps.shape()))


func test_a_missing_recipe_is_not_built() -> void:
	assert_bool(WorldMaps.is_playable("no_such_recipe")).is_false()
	assert_bool(WorldMaps.is_playable(RECIPE)).is_true()
	WorldMaps.select("no_such_recipe", SEED)
	assert_bool(WorldMaps.start_build()).is_false()
	assert_bool(WorldMaps.is_building()).is_false()
	assert_object(WorldMaps.shape()).is_null()
