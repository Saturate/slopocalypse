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
