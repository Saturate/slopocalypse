extends GdUnitTestSuite
## Ground collision tiles sampled on worker threads come out exactly as ones built right
## away, craters included.

const CONFIG := "res://modules/world/data/world.json"
const AT := Vector3(10, 0, -300)


func _world() -> VoxelWorld:
	var w: VoxelWorld = auto_free(VoxelWorld.new())
	w.config_path = CONFIG
	add_child(w)
	w.set_process(false)
	return w


static func _maps(w: VoxelWorld) -> Dictionary:
	var out := {}
	var tiles: Dictionary = w.get(&"_collision")
	for key: Vector2i in tiles:
		var body := tiles[key] as StaticBody3D
		out[key] = ((body.get_child(0) as CollisionShape3D).shape as HeightMapShape3D).map_data
	return out


func _load_threaded(w: VoxelWorld, at: Vector3) -> void:
	for frame in 600:
		w.update_around([at], 4.0, true)
		if (w.get(&"_base_jobs") as Dictionary).is_empty() and not w.get(&"_pending"):
			return
		await get_tree().process_frame
	fail("tiles never finished")


func test_threaded_collision_matches_tiles_built_right_away() -> void:
	var direct := _world()
	direct.server_dig(AT, 3.0)
	direct.update_around([AT], INF)
	var threaded := _world()
	threaded.server_dig(AT, 3.0)
	await _load_threaded(threaded, AT)
	var a := _maps(direct)
	var b := _maps(threaded)
	assert_int(b.size()).is_greater(4)
	assert_array(b.keys()).contains_exactly_in_any_order(a.keys())
	for key: Vector2i in a:
		assert_array(Array(b[key])).is_equal(Array(a[key]))
	assert_bool(threaded.is_ready_at(AT)).is_true()


func _visual_world() -> VoxelWorld:
	var w: VoxelWorld = auto_free(VoxelWorld.new())
	w.config_path = CONFIG
	# Headless runs skip visible tiles; this test is about them.
	w.set(&"_visual", true)
	add_child(w)
	w.set_process(false)
	return w


static func _tile_vertices(w: VoxelWorld) -> Dictionary:
	var out := {}
	var tiles: Dictionary = w.get(&"_tiles")
	for key: Vector2i in tiles:
		var mesh := (tiles[key] as MeshInstance3D).mesh
		out[key] = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] if mesh != null else PackedVector3Array()
	return out


func test_threaded_visible_tiles_match_ones_built_right_away() -> void:
	var direct := _visual_world()
	direct.server_dig(AT, 3.0)
	direct.update_around([AT], INF)
	var threaded := _visual_world()
	threaded.server_dig(AT, 3.0)
	for frame in 600:
		threaded.update_around([AT], 8.0, true)
		if (threaded.get(&"_tile_jobs") as Dictionary).is_empty() and not threaded.get(&"_pending"):
			break
		await get_tree().process_frame
	var a := _tile_vertices(direct)
	var b := _tile_vertices(threaded)
	assert_int(b.size()).is_greater(4)
	assert_array(b.keys()).contains_exactly_in_any_order(a.keys())
	for key: Vector2i in a:
		assert_array(Array(b[key])).override_failure_message("tile %s differs" % key).is_equal(Array(a[key]))
