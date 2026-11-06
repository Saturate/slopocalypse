extends GdUnitTestSuite


func test_every_style_builds() -> void:
	for style: String in PineTreeMesh.STYLES:
		var mesh := PineTreeMesh.build(11, 9.0, style)
		var wants_foliage: bool = PineTreeMesh.STYLES[style]["foliage"]
		assert_int(mesh.get_surface_count()).is_equal(2 if wants_foliage else 1)
		assert_int(mesh.surface_get_array_len(0)).is_greater(100)


func test_limbs_face_away_from_their_axis() -> void:
	# Any limb, at any angle, must be wound outside-out or it renders inside out.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := Vector3(0.2, 1.0, -0.3)
	var b := Vector3(1.5, 0.4, 0.8)
	PineTreeMesh._tapered_limb(st, a, b, 0.2, 0.05, 6, 3)
	st.generate_normals()
	var arrays := st.commit().surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var axis := (b - a).normalized()
	var inward := 0
	for i in range(0, verts.size(), 3):
		var centre := (verts[i] + verts[i + 1] + verts[i + 2]) / 3.0
		var on_axis := a + axis * (centre - a).dot(axis)
		if normals[i].dot(centre - on_axis) <= 0.0:
			inward += 1
	assert_int(inward).is_equal(0)


func test_pines_have_a_long_bare_trunk() -> void:
	var range_start: Array = PineTreeMesh.STYLES["pine"]["crown_start"]
	assert_float(range_start[0]).is_greater(0.5)


func test_same_seed_builds_the_same_tree() -> void:
	var a := PineTreeMesh.build(23, 10.5, "spruce")
	var b := PineTreeMesh.build(23, 10.5, "spruce")
	assert_int(a.surface_get_array_len(1)).is_equal(b.surface_get_array_len(1))
