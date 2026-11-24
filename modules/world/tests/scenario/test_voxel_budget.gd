extends GdUnitTestSuite
## Visible ground tiles are sampled and meshed off the main thread and put in nearest first,
## within a per-frame budget (#391); the ground under someone gets collision on the spot and a
## tile as soon as it is meshed, whatever the budget; a crater dug into a built tile keeps the
## old tile showing until the new one is in, and in the end every tile is the same as one
## built right away.

const CONFIG := "res://modules/world/data/world.json"
## Tiles this far round the point: few enough that a budget of nothing finishes quickly.
const REACH := 70.0


func _world() -> VoxelWorld:
	var w: VoxelWorld = auto_free(VoxelWorld.new())
	w.config_path = _near_config()
	# Headless runs skip visible tiles; this test is about them.
	w.set(&"_visual", true)
	add_child(w)
	w.set_process(false)
	return w


## The middle of a tile well away from the camp (which the world keeps built), so only that
## tile lies within the urgent reach of the point.
func _at(w: VoxelWorld) -> Vector3:
	var p := w.home + Vector3(640.0, 0.0, 0.0)
	var tile := Vector2i(floori(p.x / VoxelWorld.TILE), floori(p.z / VoxelWorld.TILE))
	var at := Vector3((tile.x + 0.5) * VoxelWorld.TILE, 0.0, (tile.y + 0.5) * VoxelWorld.TILE)
	at.y = w.ground_height(at.x, at.z)
	return at


func _tile_of(at: Vector3) -> Vector2i:
	return Vector2i(floori(at.x / VoxelWorld.TILE), floori(at.z / VoxelWorld.TILE))


## Calls `update_around` until nothing is left; returns the tiles put in by each call. Every
## tile put in has each nearer tile already in or on its way: tiles are started nearest
## first, though one meshed sooner may go in before a nearer one still meshing.
func _load(w: VoxelWorld, at: Vector3, budget: float) -> Array[Array]:
	var calls: Array[Array] = []
	var tiles: Dictionary = w.get(&"_tiles")
	var jobs: Dictionary = w.get(&"_tile_jobs")
	for frame in 3000:
		var before := {}
		for key: Vector2i in tiles:
			before[key] = tiles[key]
		w.update_around([at], budget, true)
		var put: Array = []
		for key: Vector2i in tiles:
			if before.get(key) != tiles[key]:
				put.append(key)
		var wanted: Dictionary = w.get(&"_wanted_tiles")
		for key: Vector2i in put:
			for other: Vector2i in wanted:
				if float(wanted[other]) < float(wanted[key]):
					assert_bool(tiles.has(other) or jobs.has(other)).override_failure_message("%s went in before nearer %s was started" % [key, other]).is_true()
		calls.append(put)
		if jobs.is_empty() and not w.get(&"_pending"):
			return calls
		await get_tree().process_frame
	fail("tiles never finished")
	return calls


func test_a_budget_of_nothing_puts_in_one_tile_a_call_nearest_first() -> void:
	var w := _world()
	var at := _at(w)
	var calls := await _load(w, at, 0.0)
	var count := 0
	for put: Array in calls:
		assert_int(put.size()).is_less_equal(1)
		count += put.size()
	assert_int(count).is_equal((w.get(&"_wanted_tiles") as Dictionary).size())
	assert_bool((w.get(&"_tiles") as Dictionary).has(_tile_of(at))).is_true()


func test_the_ground_under_a_point_has_collision_on_the_first_call() -> void:
	var w := _world()
	var at := _at(w)
	assert_bool(w.is_ready_at(at)).is_false()
	w.update_around([at], 0.0, true)
	assert_bool(w.is_ready_at(at)).is_true()


func test_every_tile_ends_up_as_one_built_right_away_with_no_mesh_jobs_left() -> void:
	var direct := _world()
	var at := _at(direct)
	direct.server_dig(at, 3.0)
	direct.update_around([at], INF)
	var threaded := _world()
	threaded.server_dig(at, 3.0)
	await _load(threaded, at, 2.0)
	var a: Dictionary = direct.get(&"_tiles")
	var b: Dictionary = threaded.get(&"_tiles")
	for key: Vector2i in a:
		if direct.call(&"_distance_to", key, at) > REACH:
			continue
		assert_bool(b.has(key)).override_failure_message("tile %s missing" % key).is_true()
		assert_array(Array(_vertices(b[key]))).override_failure_message("tile %s differs" % key).is_equal(Array(_vertices(a[key])))
	assert_int(VoxelGround.mesh_jobs()).is_equal(0)


func test_a_crater_keeps_the_old_tile_showing_until_the_new_one_is_in() -> void:
	var w := _world()
	var at := _at(w)
	await _load(w, at, 2.0)
	var key := _tile_of(at)
	var tiles: Dictionary = w.get(&"_tiles")
	var old: MeshInstance3D = tiles[key]
	var flat := _vertices(old)
	var collision: Dictionary = w.get(&"_collision")
	var solid := _heights(collision[key])
	w.server_dig(at, 3.0)
	# The collision has the crater at once.
	assert_array(Array(_heights(collision[key]))).is_not_equal(Array(solid))
	# The tile keeps showing on every call until its rebuild is in.
	for frame in 600:
		w.update_around([at], 0.0, true)
		assert_bool(tiles.has(key)).is_true()
		if tiles[key] != old:
			break
		await get_tree().process_frame
	assert_object(tiles[key]).is_not_same(old)
	await _load(w, at, 2.0)
	var direct := _world()
	direct.server_dig(at, 3.0)
	direct.update_around([at], INF)
	var dug := _vertices((direct.get(&"_tiles") as Dictionary)[key])
	assert_array(Array(_vertices(tiles[key]))).is_equal(Array(dug))
	assert_array(Array(dug)).is_not_equal(Array(flat))


## A crater dug while a tile is being sampled for the old ground: that job is not used, and
## the tile comes out with the crater.
func test_a_crater_dug_while_its_tile_is_sampled_ends_up_in_it() -> void:
	var w := _world()
	var at := _at(w)
	# The tile under the point is the first started, once the tiles are listed.
	var jobs: Dictionary = w.get(&"_tile_jobs")
	for frame in 120:
		w.update_around([at], 0.0, true)
		if not jobs.is_empty():
			break
		await get_tree().process_frame
	assert_bool(jobs.has(_tile_of(at))).is_true()
	w.server_dig(at, 3.0)
	await _load(w, at, 2.0)
	var direct := _world()
	direct.server_dig(at, 3.0)
	direct.update_around([at], INF)
	var key := _tile_of(at)
	assert_array(Array(_vertices((w.get(&"_tiles") as Dictionary)[key]))).is_equal(Array(_vertices((direct.get(&"_tiles") as Dictionary)[key])))


## Moving one tile across a detail ring and back while tiles are being rebuilt for it: the
## jobs no longer needed are dropped, and everything settles with no job left behind.
func test_moving_back_and_forth_across_a_detail_ring_leaves_no_jobs_behind() -> void:
	var w := _world()
	var at := _at(w)
	await _load(w, at, 2.0)
	var tiles: Dictionary = w.get(&"_tiles")
	var jobs: Dictionary = w.get(&"_tile_jobs")
	var over := at + Vector3(VoxelWorld.TILE, 0.0, 0.0)
	var rebuilding := false
	for frame in 120:
		w.update_around([over], 0.0, true)
		for key: Vector2i in jobs:
			rebuilding = rebuilding or tiles.has(key)
		if rebuilding:
			break
		await get_tree().process_frame
	assert_bool(rebuilding).is_true()
	await _load(w, at, 2.0)
	assert_dict(jobs).is_empty()
	assert_int(VoxelGround.mesh_jobs()).is_equal(0)


## After a teleport the tiles are listed again on a worker; the one under the point is
## started on the first call all the same.
func test_the_tile_under_a_teleported_point_starts_on_the_first_call() -> void:
	var w := _world()
	var at := _at(w)
	await _load(w, at, 0.0)
	var far := at + Vector3(0.0, 0.0, 640.0)
	w.update_around([far], 0.0, true)
	assert_bool((w.get(&"_tile_jobs") as Dictionary).has(_tile_of(far))).is_true()


func test_leaving_the_tree_mid_build_leaves_no_mesh_jobs() -> void:
	var w := _world()
	var at := _at(w)
	var jobs: Dictionary = w.get(&"_tile_jobs")
	var meshing := false
	for frame in 120:
		w.update_around([at], 0.0, true)
		for key: Vector2i in jobs:
			meshing = meshing or int((jobs[key] as Dictionary)["mesh"]) != 0
		if meshing:
			break
		await get_tree().process_frame
	assert_bool(meshing).is_true()
	remove_child(w)
	assert_dict(jobs).is_empty()
	assert_int(VoxelGround.mesh_jobs()).is_equal(0)


static func _heights(body: StaticBody3D) -> PackedFloat32Array:
	return ((body.get_child(0) as CollisionShape3D).shape as HeightMapShape3D).map_data


static func _vertices(tile: MeshInstance3D) -> PackedVector3Array:
	return tile.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] if tile.mesh != null else PackedVector3Array()


static func _near_config() -> String:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	(data["voxel"] as Dictionary)["load_distance"] = REACH
	var path := "user://test_voxel_budget.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	return path
