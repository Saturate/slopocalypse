extends GdUnitTestSuite
## A hand-made block stands in the world: every piece goes up with collision, and its `vary`
## keys come out differently for different placements but the same for the same one.


func _node(variation: int) -> CityBlockNode:
	var n: CityBlockNode = auto_free(CityBlockNode.new())
	n.block = CityBlock.load_named("market_square")
	n.variation_seed = variation
	add_child(n)
	n.build_all()
	return n


func test_every_piece_stands_with_collision() -> void:
	var n := _node(1)
	assert_int(n.pieces.size()).is_equal(n.block.pieces.size())
	for piece in n.pieces:
		assert_int(piece.shape_count()).is_greater(0)
	await get_tree().physics_frame
	# A ray down onto the first stall finds it.
	var stall: Vector3 = n.block.pieces[0]["at"]
	var query := PhysicsRayQueryParameters3D.create(stall + Vector3.UP * 10.0, stall + Vector3.DOWN, PhysicsLayers.SOLID)
	assert_bool(n.get_world_3d().direct_space_state.intersect_ray(query).is_empty()).is_false()


func test_vary_keys_change_per_placement_but_not_per_run() -> void:
	var paints := func(n: CityBlockNode) -> Array:
		var out: Array = []
		for piece in n.pieces:
			if piece.generator == "VoxShed":
				out.append(piece.params["paint"])
		return out
	var a: Array = paints.call(_node(1))
	var b: Array = paints.call(_node(1))
	var c: Array = paints.call(_node(2))
	assert_array(a).is_equal(b)
	assert_array(a).is_not_equal(c)
