extends GdUnitTestSuite
## Trees come down: enough bullets in one trunk, or an explosion close by. A felled tree is
## cut where it was shot: its collision becomes a stump, clients see a stump and the top
## lying where it fell, and it is still down when its chunk loads again.

const CONFIG := "res://modules/world/data/world.json"

var _scatter: SceneryScatter


func _make(visual: bool) -> void:
	_scatter = auto_free(SceneryScatter.new())
	_scatter.config_path = CONFIG
	_scatter.set(&"_visual", visual)
	_scatter.set_process(false)
	add_child(_scatter)
	_scatter.update_around([Vector3(0, 0, -150)], INF)


## The first chunk with trees in it, and its collision body.
func _chunk_with_trees() -> int:
	for i: int in _scatter.loaded_chunks():
		if _scatter.tree_count(i) > 0:
			return i
	return -1


func _body(chunk: int) -> Node:
	return ((_scatter.get(&"_chunks") as Dictionary)[chunk] as Node).get_node("Collision")


func _trunk_shapes(chunk: int) -> int:
	var count := 0
	for child: Node in _body(chunk).get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape is CapsuleShape3D and not child.has_meta(&"stump"):
			count += 1
	return count


func test_enough_bullets_fell_a_tree() -> void:
	_make(false)
	var chunk := _chunk_with_trees()
	assert_int(chunk).is_not_equal(-1)
	var id := Vector2i(chunk, 0)
	var at: Vector3 = _scatter.tree_position(id)
	var hits := int(Data.load_json(CONFIG)["scatter"]["tree_hits"])
	for n in hits - 1:
		assert_object(_scatter.server_shoot_tree(_body(chunk), at + Vector3(0.1, 1.2, 0.0))).is_null()
	var felled: Variant = _scatter.server_shoot_tree(_body(chunk), at + Vector3(0.1, 1.2, 0.0))
	assert_object(felled).is_not_null()
	assert_object((felled as Dictionary)["id"]).is_equal(id)
	# Cut where the bullets went in, give or take the tree's own scale and the dip at its foot.
	assert_float(float((felled as Dictionary)["cut"])).is_between(0.8, 1.8)


func test_a_shot_beside_a_tree_misses_it() -> void:
	_make(false)
	var chunk := _chunk_with_trees()
	var at: Vector3 = _scatter.tree_position(Vector2i(chunk, 0))
	assert_object(_scatter.tree_at(_body(chunk), at + Vector3(5.0, 1.0, 5.0))).is_not_equal(Vector2i(chunk, 0))


func test_an_explosion_knocks_down_trees_close_to_it() -> void:
	_make(false)
	var chunk := _chunk_with_trees()
	var id := Vector2i(chunk, 0)
	var at: Vector3 = _scatter.tree_position(id)
	var blasted := _scatter.server_blast_trees(at + Vector3(1.0, 0.0, 0.0), 3.0)
	assert_bool(blasted.has(id)).is_true()
	# Falls away from the blast, cut low, with a chunk blown out of it.
	assert_float((blasted[id]["direction"] as Vector3).x).is_less(0.0)
	assert_float(float(blasted[id]["cut"])).is_less_equal(TreeDamage.BLAST_CUT_MAX)
	assert_float((blasted[id]["blast"] as Vector4).w).is_greater(0.0)
	assert_bool(_scatter.server_blast_trees(at + Vector3(200.0, 0.0, 0.0), 3.0).has(id)).is_false()


func test_a_felled_tree_loses_its_collision_and_stays_down() -> void:
	_make(false)
	var chunk := _chunk_with_trees()
	var id := Vector2i(chunk, 0)
	var standing := _trunk_shapes(chunk)
	_scatter.fell_tree(id, Vector3.RIGHT, 0.8)
	assert_bool(_scatter.is_felled(id)).is_true()
	assert_int(_trunk_shapes(chunk)).is_equal(standing - 1)
	# What is left is a stump about as high as the cut.
	var stump := (_scatter.tree_record(id)["trunk"] as CollisionShape3D).shape as CapsuleShape3D
	assert_float(stump.height).is_less(1.5)
	# Gone and back: the chunk rebuilds with the tree still down.
	_scatter.call(&"_free_chunk", chunk)
	await get_tree().process_frame
	_scatter.update_around([Vector3(0, 0, -150)], INF)
	assert_int(_trunk_shapes(chunk)).is_equal(standing - 1)
	assert_object(_scatter.server_shoot_tree(_body(chunk), _scatter.tree_position(id))).is_not_equal(id)


func test_clients_see_it_lying_down() -> void:
	_make(true)
	var chunk := _chunk_with_trees()
	var id := Vector2i(chunk, 0)
	_scatter.fell_tree(id, Vector3.RIGHT, 1.0)
	# The two parts are built a step a frame.
	for n in 6:
		await get_tree().process_frame
	var node := (_scatter.get(&"_chunks") as Dictionary)[chunk] as Node
	assert_object(node.get_node_or_null("Stump0")).is_not_null()
	var fallen := node.get_node_or_null("Felled0") as Node3D
	assert_object(fallen).is_not_null()
	await get_tree().create_timer(float(Data.load_json(CONFIG)["scatter"]["tree_fall_seconds"]) + 0.3).timeout
	# Its up axis now points mostly sideways, towards where it fell.
	var up := fallen.transform.basis.y.normalized()
	assert_float(up.y).is_less(0.3)
	assert_float(up.x).is_greater(0.5)
