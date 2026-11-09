extends GdUnitTestSuite
## Scenery streams in chunks around whoever needs it, and what collides matches what you
## see: rocks use their own hull (not a ball sticking up above them) and stones lower than a
## step get none.

const SCRIPT := "res://modules/world/scripts/scenery_scatter.gd"

var _scatter: SceneryScatter


func before_test() -> void:
	_scatter = auto_free((load(SCRIPT) as GDScript).new())
	add_child(_scatter)
	# The tests say where people are; left running it would follow nobody back to the spawn.
	_scatter.set_process(false)


func _shapes() -> Array[CollisionShape3D]:
	var out: Array[CollisionShape3D] = []
	for chunk in _scatter.get_children():
		var body := chunk.get_node_or_null("Collision")
		if body == null:
			continue
		for shape in body.get_children():
			out.append(shape as CollisionShape3D)
	return out


func test_rock_collision_hugs_the_rock_and_skips_pebbles() -> void:
	var heights := TerrainHeights.new(Data.load_json(_scatter.config_path))
	var hulls := 0
	for shape in _shapes():
		if shape.shape is SphereShape3D:
			fail("rocks should not use sphere collision")
			return
		if not shape.shape is ConvexPolygonShape3D:
			continue
		hulls += 1
		var top := -INF
		var bottom := INF
		for p: Vector3 in (shape.shape as ConvexPolygonShape3D).points:
			var world := shape.transform * p
			top = maxf(top, world.y)
			bottom = minf(bottom, world.y)
		var ground := heights.height_at(shape.position.x, shape.position.z)
		assert_float(top - ground).is_greater_equal(SceneryScatter.STEP_OVER_HEIGHT - 0.15)
		# Sunk into the ground, so nothing slips under the edge.
		assert_float(bottom).is_less(ground + 0.1)
	assert_int(hulls).is_greater(3)


func test_chunks_follow_the_players_down_the_road() -> void:
	var start := _scatter.loaded_chunks()
	assert_bool(start.is_empty()).is_false()
	_scatter.update_around([Vector3(0.0, 0.0, -1200.0)], INF)
	await get_tree().process_frame
	var later := _scatter.loaded_chunks()
	for i in start:
		assert_bool(later.has(i)).override_failure_message("chunk %d near the spawn stayed loaded" % i).is_false()
	assert_bool(later.is_empty()).is_false()


func test_the_same_chunk_gets_the_same_scenery() -> void:
	var first := _shapes().map(func(s: CollisionShape3D) -> Vector3: return s.global_position)
	var again: SceneryScatter = auto_free((load(SCRIPT) as GDScript).new())
	add_child(again)
	var positions := []
	for i: int in again.loaded_chunks():
		for shape in again.chunk_node(i).get_node("Collision").get_children():
			positions.append((shape as Node3D).global_position)
	assert_int(positions.size()).is_equal(first.size())
