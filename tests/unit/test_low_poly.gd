extends GdUnitTestSuite
## Wrong winding renders black or inside-out, so check every generated normal points out.


func _assert_normals_point_out(mesh: ArrayMesh, centre: Vector3) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	assert_int(verts.size()).is_greater(0)
	var inward := 0
	for i in range(0, verts.size(), 3):
		var face_centre := (verts[i] + verts[i + 1] + verts[i + 2]) / 3.0
		if normals[i].dot(face_centre - centre) <= 0.0:
			inward += 1
	assert_int(inward).is_equal(0)


func test_chamfer_box_has_all_faces_and_outward_normals() -> void:
	var st := LowPoly.begin()
	LowPoly.chamfer_box(st, Vector3(1.0, 0.5, 2.0), 0.08, Transform3D.IDENTITY, Color.WHITE)
	var mesh := LowPoly.finish(st, LowPoly.material(0.5))
	# 6 faces + 12 edge strips as two triangles each, plus 8 corner triangles.
	assert_int(mesh.surface_get_array_len(0)).is_equal((6 + 12) * 2 * 3 + 8 * 3)
	_assert_normals_point_out(mesh, Vector3.ZERO)


func test_moved_box_still_faces_outward() -> void:
	var st := LowPoly.begin()
	var xf := Transform3D(Basis.from_euler(Vector3(0.3, 0.7, 0.1)), Vector3(2.0, 1.0, -3.0))
	LowPoly.chamfer_box(st, Vector3(0.4, 0.4, 0.4), 0.05, xf, Color.WHITE)
	_assert_normals_point_out(LowPoly.finish(st, LowPoly.material(0.5)), xf.origin)


func test_cylinder_faces_outward() -> void:
	var st := LowPoly.begin()
	LowPoly.cylinder(st, 0.3, 1.0, 8, Transform3D.IDENTITY, Color.WHITE)
	_assert_normals_point_out(LowPoly.finish(st, LowPoly.material(0.5)), Vector3.ZERO)


func test_cone_faces_outward() -> void:
	var st := LowPoly.begin()
	LowPoly.cylinder(st, 0.3, 1.0, 8, Transform3D.IDENTITY, Color.WHITE, 0.0)
	_assert_normals_point_out(LowPoly.finish(st, LowPoly.material(0.5)), Vector3.ZERO)


# A tube is not convex around its centre: the outer wall faces away from the axis, the
# inner wall toward it, and the end rings along the axis. Looking through it must work.
func test_tube_walls_face_the_right_way() -> void:
	var st := LowPoly.begin()
	LowPoly.tube(st, 0.3, 0.2, 1.0, 8, Transform3D.IDENTITY, Color.WHITE)
	var mesh := LowPoly.finish(st, LowPoly.material(0.5))
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var wrong := 0
	for i in range(0, verts.size(), 3):
		var c := (verts[i] + verts[i + 1] + verts[i + 2]) / 3.0
		var n := normals[i]
		var radial := Vector2(c.x, c.z).length()
		if absf(n.y) > 0.9:
			# End ring: faces out of the tube's end.
			if n.y * c.y <= 0.0:
				wrong += 1
		elif radial > 0.25:
			if Vector2(n.x, n.z).dot(Vector2(c.x, c.z)) <= 0.0:
				wrong += 1
		elif Vector2(n.x, n.z).dot(Vector2(c.x, c.z)) >= 0.0:
			wrong += 1
	assert_int(verts.size()).is_equal(8 * 4 * 2 * 3)
	assert_int(wrong).is_equal(0)
