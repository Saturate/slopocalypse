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


## Signed volume from the generated normals: positive and equal to the real volume only
## when every face points out, so it checks winding on concave shapes too.
func _volume(mesh: ArrayMesh) -> float:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var v := 0.0
	for i in range(0, verts.size(), 3):
		var area := (verts[i + 1] - verts[i]).cross(verts[i + 2] - verts[i]).length() / 2.0
		var c := (verts[i] + verts[i + 1] + verts[i + 2]) / 3.0
		v += c.dot(normals[i]) * area / 3.0
	return v


func test_plain_box_is_twelve_outward_triangles() -> void:
	var st := LowPoly.begin()
	LowPoly.box(st, Vector3(0.2, 0.4, 1.0), Transform3D.IDENTITY, Color.WHITE)
	var mesh := LowPoly.finish(st, LowPoly.material(0.5))
	assert_int(mesh.surface_get_array_len(0)).is_equal(36)
	assert_float(_volume(mesh)).is_equal_approx(0.08, 0.0001)


func test_a_concave_profile_extrudes_into_a_closed_solid() -> void:
	# An L seen from the side, wound both ways: 0.03 m^2 of outline, 0.1 m thick.
	var l := PackedVector2Array([Vector2(0, 0), Vector2(0.2, 0), Vector2(0.2, 0.1), Vector2(0.1, 0.1), Vector2(0.1, 0.2), Vector2(0, 0.2)])
	for outline: PackedVector2Array in [l, _reversed(l)]:
		var st := LowPoly.begin()
		LowPoly.extrude(st, outline, 0.1, Transform3D(Basis.IDENTITY, Vector3(1, 2, 3)), Color.WHITE)
		assert_float(_volume(LowPoly.finish(st, LowPoly.material(0.5)))).is_equal_approx(0.003, 0.00001)


func test_a_curved_loft_is_closed_and_faces_out() -> void:
	var rings: Array[Transform3D] = []
	for i in 6:
		var b := Basis(Vector3.RIGHT, 0.08 * i)
		rings.append(Transform3D(b, Vector3(0, -0.05 * i, -0.01 * i * i * 0.2)))
	var st := LowPoly.begin()
	LowPoly.loft(st, rings, Vector2(0.02, 0.03), Color.WHITE)
	assert_float(_volume(LowPoly.finish(st, LowPoly.material(0.5)))).is_greater(0.0)
	var straight: Array[Transform3D] = [Transform3D(Basis.IDENTITY, Vector3.ZERO), Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.5)), Transform3D(Basis.IDENTITY, Vector3(0, 0, -1.0))]
	var st2 := LowPoly.begin()
	LowPoly.loft(st2, straight, Vector2(0.1, 0.2), Color.WHITE)
	assert_float(_volume(LowPoly.finish(st2, LowPoly.material(0.5)))).is_equal_approx(0.08, 0.0001)


func _reversed(p: PackedVector2Array) -> PackedVector2Array:
	var out := p.duplicate()
	out.reverse()
	return out
