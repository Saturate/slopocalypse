extends GdUnitTestSuite
## Corner shading from voxkit's data darkens the corners of faces voxels crowd, and the
## switch turns it off.

const WHITE := Color(1, 1, 1)


func after_test() -> void:
	VoxShading.reset()


## A white floor with a white post standing on it.
static func _floor_and_post() -> VoxelModel:
	var m := VoxelModel.new()
	m.setup(Vector3(1.0, 0.5, 1.0), 0.1)
	m.fill_box(Vector3(-0.5, 0.0, -0.5), Vector3(0.5, 0.1, 0.5), WHITE, 0.0, 1)
	m.fill_box(Vector3(0.0, 0.1, 0.0), Vector3(0.1, 0.4, 0.1), WHITE, 0.0, 1)
	return m


static func _darkest(arrays: Array) -> float:
	var darkest := 1.0
	for c: Color in arrays[Mesh.ARRAY_COLOR] as PackedColorArray:
		darkest = minf(darkest, c.r)
	return darkest


func test_the_data_turns_it_on_with_its_levels() -> void:
	VoxShading.reset()
	var cfg: Dictionary = (Data.load_json(VoxShading.CONFIG) as Dictionary)["corner_shading"]
	assert_bool(cfg["on"]).is_true()
	var levels: Array = cfg["levels"]
	# The floor's corners at the post's foot are as dark as the data's darkest level there.
	var darkest := _darkest(_floor_and_post().mesh_arrays())
	assert_float(darkest).is_less(1.0)
	assert_float(darkest).is_greater_equal(float(levels[0]) - 0.001)


func test_off_leaves_every_colour_as_painted() -> void:
	VoxShading.force(PackedFloat32Array())
	assert_float(_darkest(_floor_and_post().mesh_arrays())).is_equal_approx(1.0, 0.001)


func test_ground_tiles_darken_at_the_foot_of_a_step() -> void:
	var colours := PackedColorArray([WHITE, WHITE, WHITE, WHITE])
	# Heights rise from 0 to 2 m across the tile, so the columns step up.
	var heights := PackedFloat32Array([0.0, 2.0, 0.0, 2.0])
	VoxShading.force(PackedFloat32Array([0.5, 0.65, 0.8, 1.0]))
	var shaded := VoxelGround.tile_arrays(heights, 2, 4.0, colours, 2, 8, 0.5, 100.0, WHITE, WHITE, 1.0, 1)
	VoxShading.force(PackedFloat32Array())
	var plain := VoxelGround.tile_arrays(heights, 2, 4.0, colours, 2, 8, 0.5, 100.0, WHITE, WHITE, 1.0, 1)
	# Ground colours carry their own per-column jitter; shaded corners at the steps go darker
	# than any of it.
	assert_float(_darkest(shaded)).is_less(_darkest(plain))
