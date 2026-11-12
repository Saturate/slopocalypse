extends GdUnitTestSuite
## The GPU voxel renderer (#306): the cell walk the shader does (mirrored by
## `VoxelVolume.cast`) finds the same first filled cell as sampling along the ray in tiny
## steps, and the texture holds the model's cells.


func _hollow_box() -> VoxelModel:
	var m := VoxelModel.new()
	m.setup(Vector3(2.0, 2.0, 2.0), 0.1)
	m.fill_box(Vector3(-0.8, 0.2, -0.8), Vector3(0.8, 1.8, 0.8), Color.RED, 0.0, 0)
	m.carve_box(Vector3(-0.7, 0.3, -0.7), Vector3(0.7, 1.7, 0.7))
	# A window straight through the -Z wall.
	m.carve_box(Vector3(-0.2, 0.8, -0.9), Vector3(0.2, 1.2, -0.6))
	# One thin slab inside, a voxel thick, to catch steps that jump over thin parts.
	m.fill_box(Vector3(-0.7, 0.95, -0.7), Vector3(0.7, 1.05, 0.7), Color.BLUE, 0.0, 0)
	return m


## How far along the ray the first filled cell is, found by sampling in steps far smaller
## than a cell, or -1 when it hits nothing.
func _brute(m: VoxelModel, from: Vector3, dir: Vector3) -> float:
	var n := m.cells()
	var v := m.voxel_size()
	var origin := Vector3(-n.x * v / 2.0, 0.0, -n.z * v / 2.0)
	var d := dir.normalized()
	var s := 0.0
	while s < 8.0:
		var g := (from + d * s - origin) / v
		if m.is_filled(floori(g.x), floori(g.y), floori(g.z)):
			return s
		s += STEP
	return -1.0


const STEP := 0.002


func test_the_walk_finds_the_first_filled_cell_on_random_rays() -> void:
	var m := _hollow_box()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 300:
		var from := Vector3(rng.randf_range(-3.0, 3.0), rng.randf_range(-1.0, 4.0), rng.randf_range(-3.0, 3.0))
		var to := Vector3(rng.randf_range(-0.9, 0.9), rng.randf_range(0.1, 1.9), rng.randf_range(-0.9, 0.9))
		var hit := VoxelVolume.cast(m, from, to - from, m.brick_occupancy(VoxelVolume.BRICK))
		var expected := _brute(m, from, to - from)
		if expected < 0.0:
			assert_bool(hit.is_empty()).override_failure_message("the walk hit %s where the ray misses" % [hit]).is_true()
			continue
		assert_bool(hit.is_empty()).override_failure_message("ray %d missed a surface %.3f m away" % [i, expected]).is_false()
		var found := ((hit["point"] as Vector3) - from).length()
		# The same surface: within a sampling step (a ray along a cell corner may name either
		# neighbour, at the same distance).
		assert_float(found).override_failure_message("ray %d hit at %.3f m, the surface is %.3f m away" % [i, found, expected]).is_equal_approx(expected, STEP * 2.0)
		assert_bool(m.is_filled(hit["cell"].x, hit["cell"].y, hit["cell"].z)).is_true()


func test_a_ray_through_the_window_reaches_the_slab_or_the_far_wall() -> void:
	var m := _hollow_box()
	var hit := VoxelVolume.cast(m, Vector3(0.0, 1.15, -3.0), Vector3(0.0, 0.0, 1.0), m.brick_occupancy(VoxelVolume.BRICK))
	assert_bool(hit.is_empty()).is_false()
	# Through the hole in the -Z wall, over the slab, to the inside of the +Z wall.
	assert_float((hit["point"] as Vector3).z).is_equal_approx(0.7, 0.01)
	assert_that(hit["normal"]).is_equal(Vector3(0, 0, -1))
	var wall := VoxelVolume.cast(m, Vector3(0.5, 1.5, -3.0), Vector3(0.0, 0.0, 1.0), m.brick_occupancy(VoxelVolume.BRICK))
	assert_float((wall["point"] as Vector3).z).is_equal_approx(-0.8, 0.01)


func test_a_ray_from_inside_starts_at_the_camera() -> void:
	var m := _hollow_box()
	var hit := VoxelVolume.cast(m, Vector3(0.0, 1.5, 0.0), Vector3(1.0, 0.0, 0.0), m.brick_occupancy(VoxelVolume.BRICK))
	assert_float((hit["point"] as Vector3).x).is_equal_approx(0.7, 0.01)


func test_the_texture_holds_the_cells() -> void:
	var m := _hollow_box()
	var n := m.cells()
	var bytes := m.rgba_slices()
	assert_int(bytes.size()).is_equal(n.x * n.y * n.z * 4)
	var filled := 0
	for i in range(3, bytes.size(), 4):
		if bytes[i] == 255:
			filled += 1
	assert_int(filled).is_equal(m.voxel_count())


## The cell at `c` read back out of the packed atlas the way the shader reads it: its 5-6-5
## bits, or 0 for air.
func _atlas_bits(packed: Dictionary, c: Vector3i) -> int:
	var bricks: Vector3i = packed["bricks"]
	var cells: Vector3i = packed["cells"]
	var ind: PackedByteArray = packed["indirection"]
	var atlas: PackedByteArray = packed["atlas"]
	var b := c / VoxelVolume.BRICK
	var id := ((b.z * bricks.y + b.y) * bricks.x + b.x) * 4
	if ind[id + 3] == 0:
		return 0
	var at := Vector3i(ind[id], ind[id + 1], ind[id + 2]) * VoxelVolume.BRICK + c % VoxelVolume.BRICK
	var i := ((at.z * cells.y + at.y) * cells.x + at.x) * 2
	return atlas[i] | (atlas[i + 1] << 8)


func test_the_packed_atlas_holds_every_cell_and_only_occupied_bricks() -> void:
	var m := _hollow_box()
	var packed := m.brick_atlas(VoxelVolume.BRICK, VoxelVolume.ATLAS_ROW)
	var n := m.cells()
	var dense := m.rgba_slices()
	for z in n.z:
		for y in n.y:
			for x in n.x:
				var bits := _atlas_bits(packed, Vector3i(x, y, z))
				assert_bool(bits != 0).override_failure_message("cell %d %d %d" % [x, y, z]).is_equal(m.is_filled(x, y, z))
				if bits == 0:
					continue
				# The colour survives to within one step of five or six bits.
				var i := ((z * n.y + y) * n.x + x) * 4
				assert_int(absi(((bits >> 11) & 31) * 255 / 31 - dense[i])).is_less_equal(5)
				assert_int(absi(((bits >> 5) & 63) * 255 / 63 - dense[i + 1])).is_less_equal(3)
				assert_int(absi((bits & 31) * 255 / 31 - dense[i + 2])).is_less_equal(5)
	# Fewer bricks than the whole grid's.
	var all := (packed["bricks"] as Vector3i)
	assert_int(int(packed["used"])).is_less(all.x * all.y * all.z)


func test_volumes_of_the_same_model_share_one_upload() -> void:
	var m := _hollow_box()
	var a: VoxelVolume = auto_free(VoxelVolume.new())
	var b: VoxelVolume = auto_free(VoxelVolume.new())
	a.model = m
	b.model = m
	a.refresh()
	b.refresh()
	assert_object(a.material_override).is_same(b.material_override)
	assert_object(a.mesh).is_same(b.mesh)
	var other: VoxelVolume = auto_free(VoxelVolume.new())
	other.model = _hollow_box()
	other.refresh()
	assert_object(other.material_override).is_not_same(a.material_override)
	assert_int(a.gpu_bytes).is_greater(0)
