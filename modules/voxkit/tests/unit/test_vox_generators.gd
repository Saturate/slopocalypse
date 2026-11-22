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


## Mean colour of a model's faces, to tell green leaves from dead brown ones.
func _mean_colour(model: VoxelModel) -> Color:
	var colours := model.mesh_arrays()[Mesh.ARRAY_COLOR] as PackedColorArray
	var sum := Color(0, 0, 0, 0)
	for c in colours:
		sum += c
	return sum / float(colours.size())


func test_withered_trees_lose_their_leaves_but_keep_the_trunk() -> void:
	for gen: VoxGenerator in [VoxLeafTree.new(), VoxPineTree.new()]:
		var fresh := gen.build({"seed": 7})
		var dry := gen.build({"seed": 7, "wither": 0.5})
		var bare := gen.build({"seed": 7, "wither": 1.0})
		assert_int(dry.voxel_count()).override_failure_message(gen.title() + " half withered kept all its leaves").is_less(fresh.voxel_count())
		assert_int(bare.voxel_count()).is_less(dry.voxel_count())
		# The trunk is still there.
		assert_int(bare.voxel_count()).override_failure_message(gen.title() + " withered to nothing").is_greater(0)
		# Dead leaves are browner: less green compared with red.
		var green := _mean_colour(fresh)
		var brown := _mean_colour(dry)
		assert_float(brown.g - brown.r).override_failure_message(gen.title() + " did not go brown").is_less(green.g - green.r)


## A track is laid a few centimetres proud of the ground: a hole through it shows the grass
## under it as rings and dark pits (#470), so a dirt road wears as colour only.
func test_a_worn_dirt_road_keeps_every_voxel() -> void:
	var road := VoxRoad.new()
	var base := {"seed": 7, "length": 8.0, "lanes": 1, "voxel": 0.1, "surface": VoxRoad.DIRT, "centre": 0, "edges": 0}
	var plain := base.duplicate()
	plain["wear"] = 0.0
	plain["potholes"] = 0
	var worn := base.duplicate()
	worn["wear"] = 1.0
	worn["potholes"] = 12
	assert_int(road.build(worn).voxel_count()).is_equal(road.build(plain).voxel_count())
	# Asphalt still tears and cracks.
	worn["surface"] = 0
	plain["surface"] = 0
	assert_int(road.build(worn).voxel_count()).is_less(road.build(plain).voxel_count())


## A dirt track's edges fray inward (#498): it loses cells only at its edges, by no more than
## the fray, and the wander along the way is smooth and the same for every piece that asks.
func test_a_frayed_dirt_road_wanders_in_at_its_edges_only() -> void:
	var road := VoxRoad.new()
	var base := {"seed": 7, "length": 8.0, "lanes": 1, "lane_width": 3.5, "shoulder": 0.0, "voxel": 0.1, "surface": VoxRoad.DIRT, "centre": 0, "edges": 0, "wear": 1.0}
	var frayed := base.duplicate()
	frayed["fray"] = 0.3
	var plain_model := road.build(base)
	var frayed_model := road.build(frayed)
	assert_int(frayed_model.voxel_count()).is_less(plain_model.voxel_count())
	# The middle, ruts included, is all there.
	var top := VoxRoad.BED + VoxRoad.SURFACE - 0.05
	for z: float in [-3.5, -1.0, 0.5, 3.0]:
		for x: float in [-1.3, -0.8, 0.0, 0.8, 1.3]:
			assert_bool(frayed_model.colour_at(Vector3(x, top, z)).a > 0.0 and plain_model.colour_at(Vector3(x, top, z)) == frayed_model.colour_at(Vector3(x, top, z))).override_failure_message("missing at %s, %s" % [x, z]).is_true()
	var last := VoxRoad._fray(0.0, 0.3, 4)
	for i in range(1, 400):
		var f := VoxRoad._fray(i * 0.05, 0.3, 4)
		assert_float(f).is_between(0.0, 0.3)
		assert_float(absf(f - last)).is_less(0.06)
		last = f
	assert_float(VoxRoad._fray(12.34, 0.3, 4)).is_equal(VoxRoad._fray(12.34, 0.3, 4))
