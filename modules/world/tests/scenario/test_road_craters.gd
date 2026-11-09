extends GdUnitTestSuite
## Explosions on the road break the road itself, not only the ground under it, and road
## pieces that load in after the explosion come with the crater already in them.

const CONFIG := "res://modules/world/data/world.json"
const AT_Z := -40.0

var _scatter: SceneryScatter


func before_test() -> void:
	_scatter = auto_free(SceneryScatter.new())
	_scatter.config_path = CONFIG
	# Headless runs skip visuals; the road is a visual, so build it anyway.
	_scatter.set(&"_visual", true)
	_scatter.set_process(false)
	add_child(_scatter)


func _road_point() -> Vector3:
	var heights := TerrainHeights.new(Data.load_json(CONFIG))
	return Vector3(heights.road.x_at(AT_Z), heights.road.height_at(AT_Z), AT_Z)


func _road_voxels() -> int:
	var roads: Dictionary = _scatter.get(&"_roads")
	var total := 0
	for i: int in roads:
		total += ((roads[i] as Dictionary)["model"] as VoxelModel).voxel_count()
	return total


func test_a_crater_takes_a_bite_out_of_the_road() -> void:
	var at := _road_point()
	_scatter.update_around([at], INF)
	var whole := _road_voxels()
	assert_int(whole).is_greater(0)
	_scatter.on_dug(at, 2.0)
	assert_int(_road_voxels()).is_less(whole)
	assert_dict(_scatter.get(&"_roads_dirty") as Dictionary).is_not_empty()


func test_a_crater_off_the_road_leaves_it_alone() -> void:
	var at := _road_point()
	_scatter.update_around([at], INF)
	var whole := _road_voxels()
	_scatter.on_dug(at + Vector3(30.0, 0.0, 0.0), 2.0)
	assert_int(_road_voxels()).is_equal(whole)


func test_road_loaded_later_has_the_old_crater() -> void:
	var at := _road_point()
	_scatter.update_around([at], INF)
	var whole := _road_voxels()
	for i: int in _scatter.loaded_chunks():
		_scatter.call(&"_free_chunk", i)
	assert_dict(_scatter.get(&"_roads") as Dictionary).is_empty()
	_scatter.on_dug(at, 2.0)
	_scatter.update_around([at], INF)
	assert_int(_road_voxels()).is_less(whole)
