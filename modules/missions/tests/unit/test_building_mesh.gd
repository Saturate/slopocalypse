extends GdUnitTestSuite
## Bullet holes in a building's mesh: only the chunks a hole touched are rebuilt, and every
## hole shows up on the next frame.

const CONFIG := "res://modules/missions/data/missions.json"


func _building() -> MissionBuilding:
	var cfg: Dictionary = (Data.load_json(CONFIG) as Dictionary)["buildings"]
	var b: MissionBuilding = auto_free(MissionBuilding.new())
	# No windows: a pane takes no hole, and this is about holes rebuilding chunks.
	b.spec = {"width": 6.0, "depth": 5.0, "wall_height": 3.0, "seed": 4, "paint": 1, "windows": 0.0}
	b.material_cfg = VoxMaterials.named("wood")
	# Headless runs skip the model; this test is about the model.
	b.set(&"_visual", true)
	add_child(b)
	return b


static func _area(meshes: Array[Mesh]) -> float:
	var total := 0.0
	for mesh in meshes:
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for i in range(0, idx.size(), 3):
				total += (v[idx[i + 1]] - v[idx[i]]).cross(v[idx[i + 2]] - v[idx[i]]).length() / 2.0
	return total


static func _whole_area(model: VoxelModel) -> float:
	return _area([VoxGenerator.to_mesh(model)] as Array[Mesh])


func test_thirty_holes_in_a_second_each_show_on_the_next_frame() -> void:
	var b := _building()
	var shown := b.get_node("Mesh") as VoxelChunkedMesh
	var model: VoxelModel = b.get(&"_model")
	assert_object(model).is_not_null()
	assert_int(model.chunk_count()).is_greater(1)
	assert_float(_area(shown.chunk_meshes())).is_equal_approx(_whole_area(model), 0.001)
	var w := float(b.spec["width"])
	for i in 30:
		var before := _area(shown.chunk_meshes())
		# Along the side wall, two rows up, a different spot each time.
		var local := Vector3(w / 2.0, 0.7 + 0.9 * float(i % 2), -2.0 + 0.13 * float(i))
		b.bullet_mark(b.global_transform * local)
		await get_tree().process_frame
		var after := _area(shown.chunk_meshes())
		assert_bool(is_equal_approx(after, before)).override_failure_message("hole %d did not change the mesh" % i).is_false()
		assert_float(after).override_failure_message("hole %d: the mesh differs from the model" % i).is_equal_approx(_whole_area(model), 0.001)


func test_a_hole_rebuilds_only_the_chunks_it_touched() -> void:
	var b := _building()
	var shown := b.get_node("Mesh") as VoxelChunkedMesh
	var model: VoxelModel = b.get(&"_model")
	model.carve_ellipsoid(Vector3(float(b.spec["width"]) / 2.0, 1.0, 0.0), Vector3.ONE * 0.13)
	var rebuilt := shown.refresh()
	assert_int(rebuilt).is_greater(0)
	assert_int(rebuilt).is_less(model.chunk_count() / 2)
	assert_int(shown.refresh()).is_equal(0)


func test_fallen_pieces_come_loose_as_chunks_then_go() -> void:
	var b := _building()
	b.fall_seconds = 0.1
	var cfg := LooseChunks.config()
	var saved := cfg.duplicate()
	cfg["seconds"] = 0.1
	cfg["sink_seconds"] = 0.1
	var model: VoxelModel = b.get(&"_model")
	var before := model.voxel_count()
	var wh := float(b.spec["wall_height"])
	var roof: Array = []
	for id in b.segment_count():
		if MissionBuilding.segments(6.0, 5.0, wh, b.segment_size)[id].position.y >= wh - 0.01:
			roof.append(id)
	b.break_segments([], roof)
	var chunks := get_children().filter(func(n: Node) -> bool: return n is RigidBody3D and (n as RigidBody3D).collision_layer == PhysicsLayers.DEBRIS)
	# The roof's voxels left the model and came loose as several chunks, on the debris layer.
	assert_int(chunks.size()).is_greater(1)
	assert_int((chunks[0] as RigidBody3D).collision_layer).is_equal(PhysicsLayers.DEBRIS)
	assert_int(model.voxel_count()).is_less(before)
	for id: int in roof:
		assert_bool(b.is_broken(id)).is_true()
	await get_tree().create_timer(0.6).timeout
	assert_bool(chunks.all(func(c: Variant) -> bool: return not is_instance_valid(c))).is_true()
	cfg.merge(saved, true)
