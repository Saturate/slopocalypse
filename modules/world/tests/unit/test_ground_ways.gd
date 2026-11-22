extends GdUnitTestSuite
## How the voxel ground draws what lies on it (#498): lanes painted into its columns, the
## ground tilting to meet a road strip.

const GREEN := Color(0.0, 1.0, 0.0)
## A flat 32 m tile at 0.5 m voxels.
const N := 64
const VOXEL := 0.5


func after_test() -> void:
	VoxShading.reset()


func _tile(ways: PackedFloat32Array, heights := PackedFloat32Array([1.0, 1.0, 1.0, 1.0])) -> Array:
	# Shading off: every colour is as painted.
	VoxShading.force(PackedFloat32Array())
	var colours := PackedColorArray([GREEN, GREEN, GREEN, GREEN])
	var look := {"tilt_grade": 0.34, "band": 2.0, "pad_band": 6.0, "band_grade": 1.0, "steep_slope": 1.1, "steep": Color.GRAY, "side": Color.BROWN, "skirt": 2.0}
	return VoxelGround.tile_arrays(heights, 2, 32.0, colours, 2, N, VOXEL, 1, look, ways, PackedByteArray())


## Whether `c` is the ground's own colour (alpha marks tilted tops, not colour).
static func _ground(c: Color) -> bool:
	return Color(c.r, c.g, c.b).is_equal_approx(GREEN)


## x of every top-face vertex whose colour is not the ground's.
func _painted_x(arrays: Array) -> Array[float]:
	var out: Array[float] = []
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	for i in vertices.size():
		if normals[i].y > 0.5 and not _ground(colours[i]):
			out.append(vertices[i].x)
	return out


func test_a_lane_is_painted_within_its_width_and_one_cell_of_verge() -> void:
	var half := 1.5
	# Along z through the tile's middle, a lane (kind 2).
	var lane := PackedFloat32Array([16.0, -2.0, 1.0, 16.0, 34.0, 1.0, half, Earthworks.WAY_LANE])
	var painted := _painted_x(_tile(lane))
	assert_bool(painted.is_empty()).is_false()
	for x in painted:
		# A painted cell's corners lie at most one verge cell past the edge, plus the cell.
		# A yard's or lane's edge may wander out by the fray (0.3 m by default).
		assert_float(absf(x - 16.0)).is_less_equal(half + 0.3 + VOXEL * 2.0 + 0.001)
	# Both sides of the lane reach out to the verge.
	assert_float(painted.min()).is_less(16.0 - half)
	assert_float(painted.max()).is_greater(16.0 + half)


func test_a_yard_ends_square() -> void:
	var yard := PackedFloat32Array([16.0, 8.0, 1.0, 16.0, 24.0, 1.0, 4.0, VoxelWorld.WAY_YARD])
	var arrays := _tile(yard)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	for i in vertices.size():
		if normals[i].y > 0.5 and not _ground(colours[i]):
			# Its edge wanders out by up to the yard fray (1 m by default).
			assert_float(vertices[i].z).is_between(8.0 - 1.0 - VOXEL * 2.0 - 0.001, 24.0 + 1.0 + VOXEL * 2.0 + 0.001)
			assert_float(absf(vertices[i].x - 16.0)).is_less_equal(4.0 + 1.0 + VOXEL * 2.0 + 0.001)


func test_a_road_strip_is_not_painted_on_its_shoulder() -> void:
	# A paved strip paints only its bed, under itself; nothing past its edge.
	var road := PackedFloat32Array([16.0, -2.0, 1.0, 16.0, 34.0, 1.0, 3.5, Earthworks.WAY_PAVED])
	for x in _painted_x(_tile(road)):
		assert_float(absf(x - 16.0)).is_less_equal(3.5 + 0.001)


## Sloping tilted tops carry alpha 0 so the shader varies them per column however gentle;
## level and stepped tops keep alpha 1.
func test_sloping_tilted_tops_are_marked_in_alpha() -> void:
	# Rising 5 cm across the tile: tilted, nearly level.
	var arrays := _tile(PackedFloat32Array(), PackedFloat32Array([1.0, 1.05, 1.0, 1.05]))
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var marked := 0
	for i in normals.size():
		var top := normals[i].y > 0.3
		assert_bool(colours[i].a < 0.5).is_equal(top)
		marked += 1 if top else 0
	assert_int(marked).is_greater(0)
	# Level ground: one top, unmarked.
	var level := _tile(PackedFloat32Array())
	for c: Color in level[Mesh.ARRAY_COLOR] as PackedColorArray:
		assert_float(c.a).is_equal(1.0)


## Columns a way paints carry alpha 0.75 (0 where also sloping), so the shader draws them
## with the track strip's grain; the ground's own keep 1.
func test_painted_columns_are_marked_in_alpha() -> void:
	var lane := PackedFloat32Array([16.0, -2.0, 1.0, 16.0, 34.0, 1.0, 1.5, Earthworks.WAY_LANE])
	var arrays := _tile(lane)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var marked := 0
	for i in colours.size():
		if normals[i].y < 0.3:
			continue
		var painted := not _ground(colours[i])
		assert_bool(is_equal_approx(colours[i].a, 0.75) or is_zero_approx(colours[i].a)).is_equal(painted)
		marked += 1 if painted else 0
	assert_int(marked).is_greater(0)
