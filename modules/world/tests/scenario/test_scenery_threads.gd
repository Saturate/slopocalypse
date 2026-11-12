extends GdUnitTestSuite
## Scenery chunks worked out on worker threads come out exactly as when built right away,
## and a clearing set while a plan is running still keeps its trees out.

const CONFIG := "res://modules/world/data/world.json"
const AT := Vector3(0, 0, -400)


func _scatter() -> SceneryScatter:
	var s: SceneryScatter = auto_free(SceneryScatter.new())
	s.config_path = CONFIG
	s.set(&"_visual", false)
	add_child(s)
	# After add_child: set before it, process comes back on with _ready.
	s.set_process(false)
	return s


static func _trees(s: SceneryScatter) -> Dictionary:
	var out := {}
	var all: Dictionary = s.get(&"_trees")
	for i: int in all:
		var spots: Array = []
		for t: Dictionary in all[i]:
			spots.append(t["xform"])
		out[i] = spots
	return out


## Calls the threaded update until every wanted chunk is built (a few frames at most).
func _load_threaded(s: SceneryScatter, at: Vector3) -> void:
	for frame in 600:
		s.update_around([at], 100.0, true)
		if (s.get(&"_pending") as Dictionary).is_empty():
			return
		await get_tree().process_frame
	fail("chunks never finished")


func test_threaded_chunks_match_ones_built_right_away() -> void:
	var direct := _scatter()
	direct.update_around([AT], INF)
	var threaded := _scatter()
	await _load_threaded(threaded, AT)
	var a := _trees(direct)
	var b := _trees(threaded)
	assert_int(b.size()).is_greater(1)
	assert_array(b.keys()).contains_exactly_in_any_order(a.keys())
	for i: int in a:
		assert_array(b[i]).is_equal(a[i])


func test_a_plan_from_before_a_clearing_is_not_used() -> void:
	var s := _scatter()
	var reference := _scatter()
	reference.update_around([AT], INF)
	# A spot where a tree grows, in a chunk not loaded yet in `s` beyond the spawn chunks.
	var all: Dictionary = reference.get(&"_trees")
	var chunk: int = (s.call(&"_chunk_of", AT.z) as int)
	var centre: Vector3 = ((all[chunk] as Array)[0] as Dictionary)["at"]
	s.update_around([AT], 100.0, true)
	assert_bool((s.get(&"_pending") as Dictionary).has(chunk)).is_true()
	s.set_clearings([{"at": centre, "radius": 10.0}])
	await _load_threaded(s, AT)
	for t: Dictionary in (s.get(&"_trees") as Dictionary)[chunk]:
		var at: Vector3 = t["at"]
		assert_float(Vector2(at.x - centre.x, at.z - centre.z).length()).is_greater_equal(10.0)
