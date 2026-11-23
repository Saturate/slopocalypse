class_name VoxRoad
extends VoxGenerator
## A stretch of road along z: asphalt on a gravel bed with shoulders, white edge lines, a
## centre line (dashed, solid or double), lane dividers, and wear: lighter patches, cracks
## and potholes. It can bend. A dirt surface (a track) has no asphalt to crack or tear: it
## is uneven in colour voxel by voxel, worn into two darker wheel ruts along its length, and
## its edges fray: each side wanders inward by up to `fray` metres along the way.

const ASPHALT := Color(0.2, 0.2, 0.21)
const PATCH := Color(0.27, 0.27, 0.27)
const GRAVEL := Color(0.47, 0.43, 0.37)
const WHITE := Color(0.9, 0.9, 0.86)
const YELLOW := Color(0.92, 0.72, 0.15)
const CENTRE: Array[String] = ["None", "Dashed", "Solid", "Double", "Double yellow"]
const SURFACES: Array[String] = ["Asphalt", "Dirt"]
const DIRT := 1
## A dirt surface's colour varies this much voxel by voxel (asphalt's varies 0.07).
const DIRT_JITTER := 0.14
## Wheel ruts: their middles this share of the half-width either side of the centre, this
## wide, and darker by up to this much on a fully worn track.
const RUT_AT := 0.45
const RUT_WIDTH := 0.4
const RUT_DARK := 0.2
## A frayed edge changes course every this many metres along the road.
const FRAY_STEP := 0.6
const BED := 0.2
## A tear's bites reach out to this many times its width; the bed at its bottom, and the
## broken asphalt round it.
const TEAR_BITE := 1.1
const TEAR_BED := Color(0.16, 0.15, 0.13)
const TEAR_EDGE := Color(0.42, 0.41, 0.38)
const SURFACE := 0.08


func title() -> String:
	return "Road"


func params() -> Array[Dictionary]:
	return [
		seed_param(),
		param("length", "Length (m)", 4.0, 60.0, 1.0, 24.0),
		param("lanes", "Lanes", 1.0, 4.0, 1.0, 2.0),
		param("lane_width", "Lane width (m)", 2.5, 4.0, 0.05, 3.25),
		param("shoulder", "Shoulder (m)", 0.0, 2.5, 0.1, 0.8),
		choice("centre", "Centre line", CENTRE, 1),
		choice("edges", "Edge lines", ["No", "Yes"], 1),
		param("line_width", "Line width (m)", 0.08, 0.4, 0.01, 0.15),
		param("dash", "Dash length (m)", 0.5, 8.0, 0.25, 3.0),
		param("gap", "Gap length (m)", 0.5, 12.0, 0.25, 4.5),
		param("curve", "Curve", -1.0, 1.0, 0.05, 0.0),
		param("wear", "Wear", 0.0, 1.0, 0.05, 0.35),
		param("potholes", "Potholes and tears", 0.0, 12.0, 1.0, 2.0),
		param("tear_size", "Tear size (m)", 0.3, 4.0, 0.1, 1.6),
		choice("surface", "Surface", SURFACES, 0),
		choice("ruts", "Wheel ruts (dirt)", ["No", "Yes"], 1),
		param("fray", "Frayed edges (dirt, m)", 0.0, 0.6, 0.05, 0.0),
		voxel_param(0.04, 0.25, 0.08),
	]


func build(values: Dictionary) -> VoxelModel:
	var p := with_defaults(values)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p["seed"])
	var seed := int(p["seed"])
	var length: float = p["length"]
	var lanes := int(p["lanes"])
	var lane: float = p["lane_width"]
	var shoulder: float = p["shoulder"]
	var v: float = p["voxel"]
	var half_road := lanes * lane / 2
	var half_all := half_road + shoulder
	var bend := float(p["curve"]) * length * 0.25
	# A path given by the caller (the world's road): centre x and lift y for a local z, and
	# how far it strays, so the grid is big enough. Otherwise the curve slider's bend.
	var x_of: Callable = p.get("x_of", func(z: float) -> float: return _offset(z, length, bend))
	var y_of: Callable = p.get("y_of", func(_z: float) -> float: return 0.0)
	var spread: float = p.get("spread", absf(bend))
	var rise: float = p.get("rise", 0.0)
	# A caller's own asphalt (the city's lighter streets); its patches a shade lighter still.
	var asphalt: Color = p.get("asphalt", ASPHALT)
	var patch: Color = PATCH if not p.has("asphalt") else asphalt.lightened(0.08)
	var m := new_model()
	m.setup(Vector3(half_all * 2.0 + spread * 2.0 + v * 4.0, BED + SURFACE + rise + v * 2.0, length), v)
	var top := BED + SURFACE
	var dirt := int(p["surface"]) == DIRT
	var grain := DIRT_JITTER if dirt else 0.07
	# Row by row along the length, so the road can follow its curve.
	var z := -length / 2
	while z < length / 2 - 0.0001:
		var z1 := minf(z + v, length / 2)
		var mid := (z + z1) / 2
		var c := float(x_of.call(mid))
		var y := float(y_of.call(mid))
		m.fill_box(Vector3(c - half_all, 0, z), Vector3(c + half_all, y + BED, z1), GRAVEL, 0.22, seed)
		# Shoulders level with the asphalt: lower, and the ground beside the road shows through.
		m.fill_box(Vector3(c - half_all, y + BED, z), Vector3(c - half_road, y + top, z1), GRAVEL, 0.22, seed + 1)
		m.fill_box(Vector3(c + half_road, y + BED, z), Vector3(c + half_all, y + top, z1), GRAVEL, 0.22, seed + 1)
		# A frayed edge follows the road's own metres (`z_phase`), so pieces laid end to end
		# meet; `fray_seed` tells one road's edges from another's.
		var along := mid + float(p.get("z_phase", 0.0))
		var left := _fray(along, float(p["fray"]), int(p.get("fray_seed", 0)) * 2) if dirt else 0.0
		var right := _fray(along, float(p["fray"]), int(p.get("fray_seed", 0)) * 2 + 1) if dirt else 0.0
		m.fill_box(Vector3(c - half_road + left, y + BED, z), Vector3(c + half_road - right, y + top, z1), asphalt, grain, seed + 2)
		if dirt and int(p["ruts"]) == 1 and float(p["wear"]) > 0.0:
			var rut := asphalt.darkened(RUT_DARK * float(p["wear"]))
			for side: float in [-1.0, 1.0]:
				var at := c + side * half_road * RUT_AT
				m.paint_box(Vector3(at - RUT_WIDTH / 2.0, y + BED, z), Vector3(at + RUT_WIDTH / 2.0, y + top, z1), rut, grain, seed + 3)
		z = z1
	# Dirt has no asphalt to crack or tear, and a carve through a thin dirt surface laid just
	# proud of the ground shows that ground through it (#470); round patches read as holes.
	if dirt:
		return m
	# Wear first, then the lines over it: paint only lands on asphalt that is still there, so
	# a tear or crack breaks a line, and the lines get their own chips after.
	_wear(m, p, rng, length, x_of, y_of, half_road, top, v, seed, asphalt, patch)
	z = -length / 2
	while z < length / 2 - 0.0001:
		var z1 := minf(z + v, length / 2)
		var mid := (z + z1) / 2
		_markings(m, p, float(x_of.call(mid)), z, z1, lanes, lane, half_road, float(y_of.call(mid)) + top, v)
		z = z1
	_chip_lines(m, p, rng, length, x_of, y_of, half_road, top, v, asphalt)
	return m


## How far an edge has frayed inward `along` metres down the road: a smooth wander between
## 0 and `most`, the same wherever along that is asked.
static func _fray(along: float, most: float, edge: int) -> float:
	if most <= 0.0:
		return 0.0
	var k := floorf(along / FRAY_STEP)
	var t := along / FRAY_STEP - k
	var a := _unit(edge, int(k))
	var b := _unit(edge, int(k) + 1)
	return lerpf(a, b, t * t * (3.0 - 2.0 * t)) * most


static func _unit(edge: int, knot: int) -> float:
	return float(hash([edge, knot]) & 0xFFFF) / 65535.0


func _offset(z: float, length: float, bend: float) -> float:
	var t := z / (length / 2)
	return bend * t * t


func _markings(m: VoxelModel, p: Dictionary, c: float, z0: float, z1: float, lanes: int, lane: float, half_road: float, top: float, v: float) -> void:
	var lw: float = p["line_width"]
	var paint_top := Vector2(top - v * 0.9, top + v)
	var line := func(x: float, colour: Color) -> void:
		m.paint_box(Vector3(c + x - lw / 2, paint_top.x, z0), Vector3(c + x + lw / 2, paint_top.y, z1), colour, 0.04, 0)
	if int(p["edges"]) == 1:
		line.call(-half_road + lw, WHITE)
		line.call(half_road - lw, WHITE)
	var period := float(p["dash"]) + float(p["gap"])
	# `z_phase` keeps dashes in step across road pieces laid end to end.
	var mid := (z0 + z1) / 2 + float(p.get("z_phase", 0.0))
	var in_dash := fposmod(mid, period) < float(p["dash"])
	if lanes % 2 == 1:
		# No centre between opposite directions to mark: dash every lane boundary instead.
		for i in range(1, lanes):
			if in_dash:
				line.call(-half_road + i * lane, WHITE)
		return
	match int(p["centre"]):
		1:
			if in_dash:
				line.call(0.0, WHITE)
		2:
			line.call(0.0, WHITE)
		3:
			line.call(-lw, WHITE)
			line.call(lw, WHITE)
		4:
			line.call(-lw, YELLOW)
			line.call(lw, YELLOW)
	# Dashed dividers between lanes going the same way, either side of the centre.
	for i in range(1, int(lanes / 2.0)):
		if in_dash:
			line.call(i * lane, WHITE)
			line.call(-i * lane, WHITE)


## Patches, cracks and tears, all kept on the asphalt (never out over the shoulders).
func _wear(m: VoxelModel, p: Dictionary, rng: RandomNumberGenerator, length: float, x_of: Callable, y_of: Callable, half_road: float, top: float, v: float, seed: int, asphalt: Color, patch: Color) -> void:
	var wear: float = p["wear"]
	var surface := func(x_off: float, z: float) -> Vector3:
		return Vector3(float(x_of.call(z)) + x_off, top + float(y_of.call(z)), z)
	for i in int(wear * length * 0.6):
		var z := rng.randf_range(-length / 2, length / 2)
		var size := minf(rng.randf_range(0.4, 1.6), half_road * 0.8)
		var x_off := rng.randf_range(-half_road + size, half_road - size)
		m.paint_ellipsoid(surface.call(x_off, z), Vector3(size, v * 1.5, size * rng.randf_range(0.6, 1.8)), patch if rng.randf() < 0.6 else asphalt.darkened(0.25), 0.08, seed + i)
	for i in int(wear * length * 0.4):
		var z := rng.randf_range(-length / 2, length / 2)
		_crack(m, rng, surface, rng.randf_range(-half_road, half_road) * 0.9, z, half_road, v, rng.randi_range(3, 8))
	for i in int(p["potholes"]):
		_tear(m, p, rng, surface, length, half_road, v)


## A crack: a short random walk carved one voxel deep, turned back at the road's edge.
func _crack(m: VoxelModel, rng: RandomNumberGenerator, surface: Callable, x_off: float, z: float, half_road: float, v: float, steps: int) -> void:
	var at := Vector2(x_off, z)
	var heading := rng.randf() * TAU
	for s in steps:
		heading += rng.randf_range(-0.8, 0.8)
		var next := at + Vector2(cos(heading), sin(heading)) * rng.randf_range(0.2, 0.5)
		next.x = clampf(next.x, -half_road + v, half_road - v)
		var a: Vector3 = surface.call(at.x, at.y)
		var b: Vector3 = surface.call(next.x, next.y)
		m.carve_capsule(a + Vector3.UP * v * 0.5, b + Vector3.UP * v * 0.5, v * 0.5, v * 0.5)
		at = next


## A tear: a ragged rip through the asphalt down to the gravel bed, a chain of uneven bites
## along a wandering line, with cracks running off its ends. Kept clear of the edge lines and
## the shoulders. Only the asphalt goes, so it is one shallow level with a flat bottom (a
## bite as deep as it is wide stepped down in ledges with dark walls); the bed at its bottom
## is wet and dirty, so it reads as a hole.
func _tear(m: VoxelModel, p: Dictionary, rng: RandomNumberGenerator, surface: Callable, length: float, half_road: float, v: float) -> void:
	var size := float(p["tear_size"]) * rng.randf_range(0.6, 1.3)
	var width := clampf(size * rng.randf_range(0.25, 0.5), 0.2, half_road * 0.6)
	var z := rng.randf_range(-length / 2 + size, length / 2 - size)
	# Its bites reach out to TEAR_BITE times its width: their middles stay that far in from
	# the edge lines.
	var keep := maxf(half_road - float(p["line_width"]) * 2.0 - width * TEAR_BITE, 0.0)
	var x_off := rng.randf_range(-keep, keep)
	var heading := rng.randf() * TAU
	var bites := maxi(int(size / maxf(width * 0.6, v)), 2)
	var at := Vector2(x_off, z)
	var step := size / bites
	for b in bites:
		var r := width * rng.randf_range(0.6, TEAR_BITE)
		var long := r * rng.randf_range(0.8, 1.6)
		var centre: Vector3 = surface.call(at.x, at.y)
		# Flat through the asphalt's cells and no further: an ellipsoid thinner than the
		# voxels under it reaches only the cells whose middles lie in the asphalt.
		var asphalt_mid := centre + Vector3.DOWN * SURFACE * 0.5
		var layer := SURFACE * 0.5 + v * 0.49
		m.carve_ellipsoid(asphalt_mid, Vector3(r, layer, long))
		m.paint_ellipsoid(centre + Vector3.DOWN * (SURFACE + v * 0.5), Vector3(r, v * 0.6, long), TEAR_BED, 0.1, b)
		# The broken asphalt round it is lighter, so the hole's walls read as its edge and
		# not as black slits: one cell wide and in the asphalt only, so the next bite's rim
		# never recolours this one's bed into a second level.
		m.paint_ellipsoid(asphalt_mid, Vector3(r + v, layer, long + v), TEAR_EDGE, 0.12, b + 50)
		heading += rng.randf_range(-0.6, 0.6)
		at += Vector2(cos(heading), sin(heading)) * step
		at.x = clampf(at.x, -keep, keep)
	for end in [Vector2(x_off, z), at]:
		for c in rng.randi_range(1, 3):
			_crack(m, rng, surface, end.x, end.y, half_road, v, rng.randi_range(2, 5))


## Worn paint: small spots of bare asphalt across the road, which only show where they land
## on a line.
func _chip_lines(m: VoxelModel, p: Dictionary, rng: RandomNumberGenerator, length: float, x_of: Callable, y_of: Callable, half_road: float, top: float, v: float, asphalt: Color) -> void:
	var wear: float = p["wear"]
	for i in int(wear * length * half_road * 3.0):
		var z := rng.randf_range(-length / 2, length / 2)
		var x := float(x_of.call(z)) + rng.randf_range(-half_road, half_road)
		var r := rng.randf_range(0.04, 0.14)
		m.paint_ellipsoid(Vector3(x, top + float(y_of.call(z)), z), Vector3(r, v * 1.5, r * rng.randf_range(1.0, 3.0)), asphalt, 0.07, int(p["seed"]) + 900 + i)
