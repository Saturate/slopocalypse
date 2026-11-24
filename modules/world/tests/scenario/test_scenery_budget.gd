extends GdUnitTestSuite
## Scenery chunks are put together a step at a time within a per-frame budget (#391): the
## nearest chunk first and whole before the next starts, collision, trees and rocks in the
## first step, and in the end every chunk is the same as one built right away.

const CONFIG := "res://modules/world/data/world.json"
## Metres along the highway from the camp, past what the camp loads: chunks there have road
## pieces as well as grass.
const ALONG := 400.0
const STEP_ZONES: Array[String] = ["world/scenery_build", "world/scenery_build/grass", "world/scenery_build/road_model", "world/scenery_build/road_mesh"]


func _scatter() -> SceneryScatter:
	var s: SceneryScatter = auto_free(SceneryScatter.new())
	s.config_path = _near_config(48.0)
	# Headless runs skip visuals; grass and roads are visuals, so build them anyway.
	s.set(&"_visual", true)
	add_child(s)
	# After add_child: set before it, process comes back on with _ready.
	s.set_process(false)
	return s


func _at() -> Vector3:
	return WorldMaps.shape_or_default().road_point(ALONG)


## Starts every wanted chunk's plan and waits for them all, so the steps that follow don't
## depend on which worker finishes first.
func _plans_ready(s: SceneryScatter, at: Vector3) -> void:
	s.update_around([at], 0.0, true)
	var pending: Dictionary = s.get(&"_pending")
	assert_dict(pending).is_not_empty()
	# Polled, not waited for: a task can be waited for once, and the scatter does that.
	for frame in 600:
		var done := true
		for i: int in pending:
			done = done and WorkerThreadPool.is_task_completed(int((pending[i] as Dictionary)["task"]))
		if done:
			return
		await get_tree().process_frame
	fail("plans never finished")


## Build steps run since the last call.
func _steps() -> int:
	var stats := Prof.take()
	var out := 0
	for zone: String in STEP_ZONES:
		if stats.has(zone):
			out += int((stats[zone] as Dictionary)["calls"])
	return out


func _busy(s: SceneryScatter) -> bool:
	return not (s.get(&"_pending") as Dictionary).is_empty() or not (s.get(&"_building") as Dictionary).is_empty()


func test_a_budget_of_nothing_still_takes_one_step_a_call_and_no_more() -> void:
	var s := _scatter()
	var at := _at()
	await _plans_ready(s, at)
	Prof.take()
	var calls := 0
	while _busy(s) and calls < 2000:
		s.update_around([at], 0.0, true)
		assert_int(_steps()).is_equal(1)
		calls += 1
	assert_bool(_busy(s)).is_false()
	# Grass and at least one road piece came in steps of their own after the chunks.
	assert_int(calls).is_greater(s.loaded_chunks().size() * 2)


func test_nearest_chunk_first_and_whole_before_the_next_starts() -> void:
	var s := _scatter()
	var at := _at()
	await _plans_ready(s, at)
	var here := s.chunk_at(at.x, at.z)
	var begun: Array[int] = []
	var building: Dictionary = s.get(&"_building")
	for call in 2000:
		if not _busy(s):
			break
		var before := s.loaded_chunks()
		s.update_around([at], 0.0, true)
		for i in s.loaded_chunks():
			if not before.has(i):
				# A chunk starts only once the ones before it are finished, and arrives
				# with its collision, trees and rocks.
				for earlier in begun:
					assert_bool(building.has(earlier)).is_false()
				assert_object(s.chunk_node(i).get_node_or_null("Collision")).is_not_null()
				begun.append(i)
	assert_int(begun[0]).is_equal(here)
	var points: Array[Vector3] = [at]
	for k in range(1, begun.size()):
		assert_float(float(s.call(&"_nearest", begun[k], points))).is_greater_equal(float(s.call(&"_nearest", begun[k - 1], points)))


func test_chunks_built_in_steps_match_ones_built_right_away() -> void:
	var direct := _scatter()
	var at := _at()
	direct.update_around([at], INF)
	var stepped := _scatter()
	await _plans_ready(stepped, at)
	for call in 2000:
		if not _busy(stepped):
			break
		stepped.update_around([at], 4.0, true)
		await get_tree().process_frame
	assert_bool(_busy(stepped)).is_false()
	assert_array(stepped.loaded_chunks()).contains_exactly_in_any_order(direct.loaded_chunks())
	assert_array((stepped.get(&"_roads") as Dictionary).keys()).contains_exactly_in_any_order((direct.get(&"_roads") as Dictionary).keys())
	for i in direct.loaded_chunks():
		assert_int(_shapes(stepped, i)).is_equal(_shapes(direct, i))
		assert_int(stepped.tree_count(i)).is_equal(direct.tree_count(i))
	var a: Dictionary = direct.get(&"_grass_cells")
	var b: Dictionary = stepped.get(&"_grass_cells")
	assert_array(b.keys()).contains_exactly_in_any_order(a.keys())
	for cell: Vector2i in a:
		assert_array((b[cell] as MultiMeshInstance3D).multimesh.buffer).is_equal((a[cell] as MultiMeshInstance3D).multimesh.buffer)


func test_grass_buffers_hold_each_tuft_where_it_was_placed() -> void:
	var s := _scatter()
	var xform := Transform3D(Basis(Vector3.UP, 0.7).scaled(Vector3(0.8, 1.2, 0.8)), Vector3(70.0, 3.0, 20.0))
	var colour := Color(0.3, 0.4, 0.2)
	var cell := Vector2i(2, 0)
	var per_cell: Dictionary[Vector2i, Array] = {cell: [[xform], [colour]]}
	var buffer: PackedFloat32Array = (s.call(&"_grass_buffers", per_cell) as Dictionary)[cell]
	var centre: Vector3 = s.call(&"_grass_centre", cell)
	var local := Transform3D(xform.basis, xform.origin - centre)
	var read := Transform3D(Vector3(buffer[0], buffer[4], buffer[8]), Vector3(buffer[1], buffer[5], buffer[9]), Vector3(buffer[2], buffer[6], buffer[10]), Vector3(buffer[3], buffer[7], buffer[11]))
	assert_bool(read.is_equal_approx(local)).is_true()
	assert_bool(Color(buffer[12], buffer[13], buffer[14], buffer[15]).is_equal_approx(colour)).is_true()


func test_a_build_right_away_finishes_chunks_streaming_left_half_built() -> void:
	var s := _scatter()
	var at := _at()
	await _plans_ready(s, at)
	s.update_around([at], 0.0, true)
	assert_dict(s.get(&"_building") as Dictionary).is_not_empty()
	s.update_around([at], INF)
	assert_dict(s.get(&"_building") as Dictionary).is_empty()


func test_the_server_builds_collision_only_and_leaves_nothing_half_built() -> void:
	var s := _scatter()
	s.set(&"_visual", false)
	# The camp's chunks were built when it was added, with grass and roads.
	var grass := (s.get(&"_grass_cells") as Dictionary).size()
	var roads := (s.get(&"_roads") as Dictionary).size()
	var at := _at()
	await _plans_ready(s, at)
	for call in 200:
		if not _busy(s):
			break
		s.update_around([at], 0.0, true)
	assert_bool(_busy(s)).is_false()
	assert_int(s.loaded_chunks().size()).is_greater(0)
	assert_int((s.get(&"_grass_cells") as Dictionary).size()).is_less_equal(grass)
	assert_int((s.get(&"_roads") as Dictionary).size()).is_less_equal(roads)


func test_a_crater_dug_while_grass_is_planned_still_clears_it() -> void:
	var s := _scatter()
	var at := _at()
	await _plans_ready(s, at)
	var here := s.chunk_at(at.x, at.z)
	var area: Rect2 = s.call(&"_chunk_area", here)
	# Off the road, in the middle of the chunk: grass grows round there.
	var spot := Vector3(area.get_center().x, 0.0, area.get_center().y)
	spot.y = WorldMaps.shape_or_default().height_at(spot.x, spot.z)
	s.clear_grass(spot, 6.0)
	for call in 2000:
		if not _busy(s):
			break
		s.update_around([at], 4.0, true)
	# Read from the buffer: a headless run's MultiMesh gives back the buffer it was given but
	# not single instances.
	var near := 0
	var hidden := 0
	for inst: MultiMeshInstance3D in (s.get(&"_grass_cells") as Dictionary).values():
		var buffer := inst.multimesh.buffer
		for b in range(0, buffer.size(), SceneryScatter.GRASS_STRIDE):
			var origin := Vector3(buffer[b + 3], buffer[b + 7], buffer[b + 11]) + inst.position
			if buffer[b] == 0.0 and buffer[b + 5] == 0.0 and buffer[b + 10] == 0.0:
				hidden += 1
			elif origin.distance_to(spot) < 6.0:
				near += 1
	assert_int(hidden).is_greater(0)
	assert_int(near).is_equal(0)


func _shapes(s: SceneryScatter, i: int) -> int:
	var node := s.chunk_node(i)
	var total := 0
	for body: String in ["Collision", "SightBlockers"]:
		var n := node.get_node_or_null(body)
		if n != null:
			total += n.get_child_count()
	return total


## world.json with scenery built only `reach` metres round whoever needs it: the map has
## many roads, and building every piece within the full load distance costs seconds a test.
static func _near_config(reach: float) -> String:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	(data["scatter"] as Dictionary)["load_distance"] = reach
	var path := "user://test_scenery_budget.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	return path
