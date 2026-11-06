extends GdUnitTestSuite


func test_has_bark_and_foliage_surfaces() -> void:
	var mesh := PineTreeMesh.build(11, 8.0)
	assert_int(mesh.get_surface_count()).is_equal(2)
	assert_int(mesh.surface_get_array_len(1)).is_greater(300)


func test_bark_faces_outward() -> void:
	var mesh := PineTreeMesh.build(11, 8.0)
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var inward := 0
	for i in range(0, verts.size(), 3):
		var centre := (verts[i] + verts[i + 1] + verts[i + 2]) / 3.0
		if normals[i].dot(Vector3(centre.x, 0.0, centre.z)) <= 0.0:
			inward += 1
	assert_int(inward).is_equal(0)


func test_same_seed_builds_the_same_tree() -> void:
	var a := PineTreeMesh.build(23, 10.5)
	var b := PineTreeMesh.build(23, 10.5)
	assert_int(a.surface_get_array_len(1)).is_equal(b.surface_get_array_len(1))
