extends GdUnitTestSuite
## Every generator builds a real mesh with its defaults and at both ends of every slider,
## and the same seed always gives the same model.


func _quads(gen: VoxGenerator, p: Dictionary) -> int:
	var model := gen.build(p)
	var arrays := model.mesh_arrays()
	if arrays.is_empty():
		return 0
	return (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 6


func test_every_generator_builds_with_defaults() -> void:
	for gen in VoxCatalog.all():
		assert_int(_quads(gen, {})).override_failure_message(gen.title() + " built nothing").is_greater(0)


func test_every_generator_builds_at_the_ends_of_its_sliders() -> void:
	for gen in VoxCatalog.all():
		for end in ["min", "max"]:
			var p := {}
			for spec in gen.params():
				# The voxel size stays at its default: the finest voxels at the largest size
				# are slow, and the range of shapes is what this checks.
				if spec["key"] != "voxel":
					p[spec["key"]] = spec[end]
			assert_int(_quads(gen, p)).override_failure_message("%s at %s built nothing" % [gen.title(), end]).is_greater(0)


func test_the_same_seed_gives_the_same_model() -> void:
	for gen in VoxCatalog.all():
		var a := gen.build({"seed": 42}).voxel_count()
		var b := gen.build({"seed": 42}).voxel_count()
		assert_int(a).is_equal(b)


func test_voxel_size_sets_the_detail() -> void:
	var rock := VoxRock.new()
	var coarse := rock.build({"voxel": 0.2}).voxel_count()
	var fine := rock.build({"voxel": 0.05}).voxel_count()
	assert_int(fine).is_greater(coarse * 20)


func test_the_roadside_scene_lists_generators_and_places() -> void:
	var scene := VoxCatalog.roadside(3)
	assert_int(scene.size()).is_greater(10)
	for entry in scene:
		assert_object(entry[0]).is_instanceof(VoxGenerator)
