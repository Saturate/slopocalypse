class_name LowPoly
extends RefCounted
## Builders for flat-shaded low-poly shapes that read better than primitive meshes:
## chamfered boxes (bevelled edges catch light) and faceted cylinders. Parts are appended
## to a SurfaceTool with a vertex colour, so a whole model can be one mesh per material.


## Starts a SurfaceTool for a model surface. Finish with `finish(st, material)`.
static func begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


## Flat normals, then commit into `mesh` (or a new ArrayMesh) with the material.
static func finish(st: SurfaceTool, material: Material, mesh: ArrayMesh = null) -> ArrayMesh:
	st.generate_normals()
	var out := st.commit(mesh)
	out.surface_set_material(out.get_surface_count() - 1, material)
	return out


## Vertex-coloured, sRGB-correct material; colour comes from each part.
static func material(roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = roughness
	m.metallic = metallic
	return m


## A box of `size` with every edge bevelled by `bevel`: 6 faces, 12 edge strips, 8 corners.
static func chamfer_box(st: SurfaceTool, size: Vector3, bevel: float, xf: Transform3D, colour: Color) -> void:
	var h := size / 2.0
	var b := minf(bevel, minf(h.x, minf(h.y, h.z)) * 0.9)
	# Per corner (signs sx, sy, sz): the point on the X face, the Y face and the Z face.
	var corner := func(sx: float, sy: float, sz: float) -> Array[Vector3]:
		return [
			Vector3(sx * h.x, sy * (h.y - b), sz * (h.z - b)),
			Vector3(sx * (h.x - b), sy * h.y, sz * (h.z - b)),
			Vector3(sx * (h.x - b), sy * (h.y - b), sz * h.z),
		]
	var c := {}
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				c[Vector3(sx, sy, sz)] = corner.call(sx, sy, sz)
	var quads: Array = []
	# Main faces: axis index 0/1/2 picks which point of each corner lies on that face.
	for axis in 3:
		for s in [-1.0, 1.0]:
			var pts: Array[Vector3] = []
			for u in [-1.0, 1.0]:
				for v in [-1.0, 1.0]:
					var key := Vector3.ZERO
					key[axis] = s
					key[(axis + 1) % 3] = u
					key[(axis + 2) % 3] = v
					pts.append(c[key][axis])
			quads.append([pts[0], pts[1], pts[3], pts[2]])
	# Edge strips between two faces, running along the third axis.
	for axis in 3:
		var a1 := (axis + 1) % 3
		var a2 := (axis + 2) % 3
		for s1 in [-1.0, 1.0]:
			for s2 in [-1.0, 1.0]:
				var k_lo := Vector3.ZERO
				k_lo[a1] = s1
				k_lo[a2] = s2
				k_lo[axis] = -1.0
				var k_hi := k_lo
				k_hi[axis] = 1.0
				quads.append([c[k_lo][a1], c[k_hi][a1], c[k_hi][a2], c[k_lo][a2]])
	for q: Array in quads:
		_tri(st, q[0], q[1], q[2], xf, colour)
		_tri(st, q[0], q[2], q[3], xf, colour)
	for key: Vector3 in c:
		var p: Array = c[key]
		_tri(st, p[0], p[1], p[2], xf, colour)


## Faceted cylinder along local Y, centred on the origin.
static func cylinder(st: SurfaceTool, radius: float, height: float, sides: int, xf: Transform3D, colour: Color, top_radius: float = -1.0) -> void:
	var r_top := radius if top_radius < 0.0 else top_radius
	var y0 := -height / 2.0
	var y1 := height / 2.0
	for i in sides:
		var a0 := TAU * float(i) / sides
		var a1 := TAU * float(i + 1) / sides
		var b0 := Vector3(cos(a0) * radius, y0, sin(a0) * radius)
		var b1 := Vector3(cos(a1) * radius, y0, sin(a1) * radius)
		var t0 := Vector3(cos(a0) * r_top, y1, sin(a0) * r_top)
		var t1 := Vector3(cos(a1) * r_top, y1, sin(a1) * r_top)
		_tri(st, b0, b1, t1, xf, colour)
		_tri(st, b0, t1, t0, xf, colour)
		_tri(st, Vector3(0, y0, 0), b1, b0, xf, colour)
		if r_top > 0.0:
			_tri(st, Vector3(0, y1, 0), t0, t1, xf, colour)


## Emits a triangle facing away from the shape's own origin. Every shape here is convex
## and centred before `xf` is applied, so this fixes winding without bookkeeping.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, xf: Transform3D, colour: Color) -> void:
	var n := (b - a).cross(c - a)
	# Cones collapse one side triangle to a point; zero-area faces get garbage normals.
	if n.length_squared() < 1e-12:
		return
	var centre := (a + b + c) / 3.0
	# Godot treats clockwise-from-the-front as front-facing, so the cross product of a front
	# face points inward; flip when it points outward.
	if n.dot(centre) > 0.0:
		var t := b
		b = c
		c = t
	st.set_color(colour)
	st.add_vertex(xf * a)
	st.set_color(colour)
	st.add_vertex(xf * b)
	st.set_color(colour)
	st.add_vertex(xf * c)
