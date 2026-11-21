class_name WireMesh
extends RefCounted
## Builds one mesh holding many wire pieces at one detail step: thin tubes along each sag
## curve, and barbs where the kind has them. No nodes and no collision.
##
## A piece is a stretch of one span: {a, b, sag (metres), t0, t1, kind (the kind's data with
## `radius` and linear `color` filled in)}.


## Builds one unit of work ({step, begin, origin, ...} from the wires module) into
## `unit.arrays`, with the time it took in `unit.usec`. Runs on a worker thread.
static func fill(unit: Dictionary, pieces: Array, steps: Array, sides: int) -> void:
	var started := Time.get_ticks_usec()
	unit["arrays"] = arrays(pieces, steps[int(unit["step"])], float(unit["begin"]), steps, sides, unit["origin"])
	unit["usec"] = Time.get_ticks_usec() - started


## The arrays for `pieces` drawn at `step` (one entry of the data's `lod`), with positions
## relative to `origin`. Empty when there is nothing to draw. Pure: touches nothing but its
## arguments, so it runs on a worker thread.
static func arrays(pieces: Array, step: Dictionary, begin: float, steps: Array, sides: int, origin: Vector3) -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var barbs := bool(step.get("barbs", false))
	var ring := _ring(sides)
	for piece: Dictionary in pieces:
		var kind: Dictionary = piece["kind"]
		var a: Vector3 = piece["a"]
		var b: Vector3 = piece["b"]
		var sag := float(piece["sag"])
		var t0 := float(piece["t0"])
		var t1 := float(piece["t1"])
		var length := a.distance_to(b) * (t1 - t0)
		var segments := WireCurve.segments_at(length, float(kind["segment_length"]), begin, steps)
		var line := WireCurve.points_between(a, b, sag, t0, t1, segments)
		var colour: Color = kind["color"]
		_tube(line, float(kind["radius"]), float(kind["radius"]), ring, colour, origin, verts, normals, colours, uvs, indices)
		if barbs and kind.has("barbs"):
			_barbs(a, b, sag, t0, t1, kind["barbs"], ring, colour, origin, verts, normals, colours, uvs, indices)
	if verts.is_empty():
		return []
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_COLOR] = colours
	out[Mesh.ARRAY_TEX_UV] = uvs
	out[Mesh.ARRAY_INDEX] = indices
	return out


## A tube through `line`. `widen` goes to the shader as the radius it may push out from (0
## keeps it as built).
## Cosines then sines of the corners round a wire, worked out once per mesh. Corners sit half
## a step round, so a face (not an edge) looks sideways: a wire seen from the side then
## shades evenly instead of lit above and dark below.
static func _ring(sides: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(sides * 2)
	for k in sides:
		var angle := TAU * (float(k) + 0.5) / float(sides)
		out[k] = cos(angle)
		out[sides + k] = sin(angle)
	return out


static func _tube(line: PackedVector3Array, radius: float, widen: float, ring: PackedFloat32Array, colour: Color, origin: Vector3,
		verts: PackedVector3Array, normals: PackedVector3Array, colours: PackedColorArray, uvs: PackedVector2Array, indices: PackedInt32Array) -> void:
	var n := line.size()
	if n < 2:
		return
	var sides := ring.size() / 2
	var first := verts.size()
	var count := n * sides
	verts.resize(first + count)
	normals.resize(first + count)
	colours.resize(first + count)
	uvs.resize(first + count)
	var uv := Vector2(widen, 0.0)
	var v := first
	for i in n:
		var frame := _frame(line[mini(i + 1, n - 1)] - line[maxi(i - 1, 0)])
		var centre := line[i] - origin
		for k in sides:
			var out_dir: Vector3 = frame[0] * ring[k] + frame[1] * ring[sides + k]
			verts[v] = centre + out_dir * radius
			normals[v] = out_dir
			colours[v] = colour
			uvs[v] = uv
			v += 1
	var at := indices.size()
	indices.resize(at + (n - 1) * sides * 6)
	for i in n - 1:
		for k in sides:
			var a := first + i * sides + k
			var b := first + i * sides + (k + 1) % sides
			# Clockwise seen from outside, Godot's front face.
			indices[at] = a
			indices[at + 1] = b
			indices[at + 2] = a + sides
			indices[at + 3] = b
			indices[at + 4] = b + sides
			indices[at + 5] = a + sides
			at += 6


## Shares along a span `span` metres long where barbs sit within [t0, t1): every `spacing`
## metres, counted from the span's start so they don't shift where it is cut into pieces.
## Pieces meet at t1 = the next one's t0, so each barb falls in exactly one.
static func barb_ts(span: float, spacing: float, t0: float, t1: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if span <= 0.0 or spacing <= 0.0:
		return out
	var j := maxi(floori(t0 * span / spacing - 0.5), 0)
	while true:
		var t := (float(j) + 0.5) * spacing / span
		if t >= t1 or t >= 1.0:
			break
		if t >= t0:
			out.append(t)
		j += 1
	return out


## Two short crossed spikes through the wire at each barb.
static func _barbs(a: Vector3, b: Vector3, sag: float, t0: float, t1: float, barbs: Dictionary, ring: PackedFloat32Array, colour: Color, origin: Vector3,
		verts: PackedVector3Array, normals: PackedVector3Array, colours: PackedColorArray, uvs: PackedVector2Array, indices: PackedInt32Array) -> void:
	var span := a.distance_to(b)
	var spacing := float(barbs.get("spacing", 0.25))
	var half := float(barbs.get("length", 0.07)) * 0.5
	var radius := float(barbs.get("thickness", 0.006)) * 0.5
	for t in barb_ts(span, spacing, t0, t1):
		var at := WireCurve.point_at(a, b, sag, t)
		var along := WireCurve.point_at(a, b, sag, minf(t + 0.01, 1.0)) - WireCurve.point_at(a, b, sag, maxf(t - 0.01, 0.0))
		var frame := _frame(along)
		# Each barb turned a little from the last, as the strands are twisted.
		var turn := t * span / spacing * 0.9
		for spike in 2:
			var angle := turn + float(spike) * PI * 0.5
			var dir := frame[0] * cos(angle) + frame[1] * sin(angle)
			_tube(PackedVector3Array([at - dir * half, at + dir * half]), radius, 0.0, ring, colour, origin, verts, normals, colours, uvs, indices)


## Two unit directions square to `along` and to each other: sideways, then up.
static func _frame(along: Vector3) -> Array[Vector3]:
	var tangent := along.normalized() if along.length_squared() > 1e-12 else Vector3.RIGHT
	var side := tangent.cross(Vector3.UP)
	if side.length_squared() < 1e-6:
		side = tangent.cross(Vector3.RIGHT)
	side = side.normalized()
	return [side, side.cross(tangent).normalized()]
