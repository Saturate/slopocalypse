extends GdUnitTestSuite
## Explosions on the road break the road itself, not only the ground under it, and road
## pieces that load in after the explosion come with the crater already in them.

const CONFIG := "res://modules/world/data/world.json"
## Metres along the highway from the camp.
const ALONG := 40.0

var _scatter: SceneryScatter


func before_test() -> void:
	_scatter = auto_free(SceneryScatter.new())
	_scatter.config_path = _near_config(48.0)
	# Headless runs skip visuals; the road is a visual, so build it anyway.
	_scatter.set(&"_visual", true)
	_scatter.set_process(false)
	add_child(_scatter)


func _road_point() -> Vector3:
	return WorldMaps.shape_or_default().road_point(ALONG)


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
	var side := WorldMaps.shape_or_default().forward().cross(Vector3.UP)
	_scatter.on_dug(at + side * 30.0, 2.0)
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


## world.json with scenery built only `reach` metres round whoever needs it: the map has
## many roads, and building every piece within the full load distance costs seconds a test.
static func _near_config(reach: float) -> String:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	(data["scatter"] as Dictionary)["load_distance"] = reach
	var path := "user://test_world_near.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	return path
