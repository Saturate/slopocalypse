class_name LowPoly
extends RefCounted
## Builders for flat-shaded low-poly shapes that read better than primitive meshes:
## chamfered boxes (bevelled edges catch light) and faceted cylinders. Parts are appended
## to a SurfaceTool with a vertex colour, so a whole model can be one mesh per material.


## Starts a SurfaceTool for a model surface. Finish with `finish(st, material)`.
static func begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Without this, generate_normals smooths across vertices that share a position, so
	# cylinders and tubes come out round and soft instead of faceted.
	st.set_smooth_group(-1)
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


## Open tube along local Y, centred on the origin: outer wall, inner wall and the two end
## rings, so it can be looked through (sight housings, muzzle devices).
static func tube(st: SurfaceTool, outer: float, inner: float, height: float, sides: int, xf: Transform3D, colour: Color) -> void:
	var y0 := -height / 2.0
	var y1 := height / 2.0
	for i in sides:
		var a0 := TAU * float(i) / sides
		var a1 := TAU * float(i + 1) / sides
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var out_dir := (d0 + d1).normalized()
		var o00 := d0 * outer + Vector3(0, y0, 0)
		var o10 := d1 * outer + Vector3(0, y0, 0)
		var o01 := d0 * outer + Vector3(0, y1, 0)
		var o11 := d1 * outer + Vector3(0, y1, 0)
		var i00 := d0 * inner + Vector3(0, y0, 0)
		var i10 := d1 * inner + Vector3(0, y0, 0)
		var i01 := d0 * inner + Vector3(0, y1, 0)
		var i11 := d1 * inner + Vector3(0, y1, 0)
		_quad_facing(st, o00, o10, o11, o01, out_dir, xf, colour)
		_quad_facing(st, i00, i10, i11, i01, -out_dir, xf, colour)
		_quad_facing(st, o01, o11, i11, i01, Vector3.UP, xf, colour)
		_quad_facing(st, o00, o10, i10, i00, Vector3.DOWN, xf, colour)


## A plain box: 12 triangles, for small repeated detail (rail teeth, slots) where bevels
## would cost more than they show.
static func box(st: SurfaceTool, size: Vector3, xf: Transform3D, colour: Color) -> void:
	var h := size / 2.0
	for axis in 3:
		for s in [-1.0, 1.0]:
			var u := (axis + 1) % 3
			var v := (axis + 2) % 3
			var pts: Array[Vector3] = []
			for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var p := Vector3.ZERO
				p[axis] = s * h[axis]
				p[u] = corner.x * h[u]
				p[v] = corner.y * h[v]
				pts.append(p)
			_tri(st, pts[0], pts[1], pts[2], xf, colour)
			_tri(st, pts[0], pts[2], pts[3], xf, colour)


## A side profile pushed out sideways: `profile` is the outline seen from the side, as
## (z, y) points (guns point down -Z), in either winding and may be concave. The solid is
## `thickness` wide along X, centred. Gives real silhouettes: stocks, grips, receivers.
static func extrude(st: SurfaceTool, profile: PackedVector2Array, thickness: float, xf: Transform3D, colour: Color) -> void:
	var n := profile.size()
	if n < 3:
		return
	var hx := thickness / 2.0
	var tris := Geometry2D.triangulate_polygon(profile)
	for i in range(0, tris.size(), 3):
		var pa := profile[tris[i]]
		var pb := profile[tris[i + 1]]
		var pc := profile[tris[i + 2]]
		for side in [-1.0, 1.0]:
			_tri_facing(st, Vector3(side * hx, pa.y, pa.x), Vector3(side * hx, pb.y, pb.x), Vector3(side * hx, pc.y, pc.x), Vector3(side, 0, 0), xf, colour)
	# Outward is to the right of each edge for a clockwise outline, to the left otherwise.
	var ccw := _signed_area(profile) > 0.0
	for i in n:
		var a := profile[i]
		var b := profile[(i + 1) % n]
		var e := b - a
		var out2 := Vector2(e.y, -e.x) if ccw else Vector2(-e.y, e.x)
		var facing := Vector3(0, out2.y, out2.x)
		_quad_facing(st, Vector3(-hx, a.y, a.x), Vector3(hx, a.y, a.x), Vector3(hx, b.y, b.x), Vector3(-hx, b.y, b.x), facing, xf, colour)


## A rectangular section swept through `rings` (each ring's origin is the section centre,
## its X and Y axes the section's width and height directions), capped at both ends. Curved
## magazines and bent shapes without stair steps.
static func loft(st: SurfaceTool, rings: Array[Transform3D], half: Vector2, colour: Color) -> void:
	var corners: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	var pts: Array[PackedVector3Array] = []
	for r in rings:
		var ring := PackedVector3Array()
		for c in corners:
			ring.append(r * Vector3(c.x * half.x, c.y * half.y, 0.0))
		pts.append(ring)
	for k in rings.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var mid := (rings[k].origin + rings[k + 1].origin) / 2.0
		for i in 4:
			var j := (i + 1) % 4
			var centre := (a[i] + a[j] + b[i] + b[j]) / 4.0
			_quad_facing(st, a[i], a[j], b[j], b[i], centre - mid, Transform3D.IDENTITY, colour)
	var first := pts[0]
	var last := pts[pts.size() - 1]
	var dir0 := rings[0].origin - rings[1].origin
	var dir1 := rings[rings.size() - 1].origin - rings[rings.size() - 2].origin
	_quad_facing(st, first[0], first[1], first[2], first[3], dir0, Transform3D.IDENTITY, colour)
	_quad_facing(st, last[0], last[1], last[2], last[3], dir1, Transform3D.IDENTITY, colour)


static func _signed_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return a / 2.0


static func _quad_facing(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, facing: Vector3, xf: Transform3D, colour: Color) -> void:
	_tri_facing(st, a, b, c, facing, xf, colour)
	_tri_facing(st, a, c, d, facing, xf, colour)


## Emits a triangle whose front faces along `facing`, for shapes that are not convex
## around their origin (the inside of a tube faces inward).
static func _tri_facing(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, facing: Vector3, xf: Transform3D, colour: Color) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	# Clockwise from the front is front-facing, so a front face's cross product points
	# against `facing`.
	if n.dot(facing) > 0.0:
		var t := b
		b = c
		c = t
	for v: Vector3 in [a, b, c]:
		st.set_color(colour)
		st.add_vertex(xf * v)


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
