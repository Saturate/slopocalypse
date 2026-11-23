class_name VoxLattice
extends RefCounted
## Steel lattice shared by the kit's towers (the radio mast, the power pylon): straight members
## drawn as short capsules, and a square body of four corner legs with a ring and crossed
## diagonals on every face of each bay. Colours come from a callable of the height, so a
## mast can be painted in bands.

## Members are drawn in pieces this long, so each takes the colour at its own height.
const PIECE := 0.5
## Colour noise on steel members.
const JITTER := 0.04
const CORNERS: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]


## A straight member from `a` to `b`, `r` thick, coloured by `paint(height)`.
static func bar(m: VoxelModel, a: Vector3, b: Vector3, r: float, paint: Callable, seed: int) -> void:
	var pieces := maxi(ceili(a.distance_to(b) / PIECE), 1)
	for k in pieces:
		var p0 := a.lerp(b, float(k) / pieces)
		var p1 := a.lerp(b, float(k + 1) / pieces)
		var colour: Color = paint.call((p0.y + p1.y) * 0.5)
		m.fill_capsule(p0, p1, r, r, colour, JITTER, seed)


## A body from `y0` to `y1`: four legs at the corners of a rectangle `size(height)` across
## (Vector2: along x, along z), and every `bay` metres a ring round it with crossed diagonals
## on each face; centred on `at` across the ground.
static func body(m: VoxelModel, y0: float, y1: float, size: Callable, bay: float, leg_r: float, brace_r: float, paint: Callable, seed: int, at := Vector3.ZERO) -> void:
	for c in CORNERS:
		bar(m, at + corner(c, size, y0), at + corner(c, size, y1), leg_r, paint, seed)
	var y := y0
	while y < y1 - 0.01:
		var top := minf(y + bay, y1)
		for k in 4:
			var a := CORNERS[k]
			var b := CORNERS[(k + 1) % 4]
			bar(m, at + corner(a, size, top), at + corner(b, size, top), brace_r, paint, seed)
			bar(m, at + corner(a, size, y), at + corner(b, size, top), brace_r, paint, seed)
			bar(m, at + corner(b, size, y), at + corner(a, size, top), brace_r, paint, seed)
		y = top


## Where leg `c` (a corner, each axis -1 or 1) stands at `y`.
static func corner(c: Vector2, size: Callable, y: float) -> Vector3:
	var across: Vector2 = size.call(y)
	return Vector3(c.x * across.x / 2.0, y, c.y * across.y / 2.0)
