class_name VoxRoad
extends VoxGenerator
## A stretch of road along z: asphalt on a gravel bed with shoulders, white edge lines, a
## centre line (dashed, solid or double), lane dividers, and wear: lighter patches, cracks
## and potholes. It can bend.

const ASPHALT := Color(0.2, 0.2, 0.21)
const PATCH := Color(0.27, 0.27, 0.27)
const GRAVEL := Color(0.47, 0.43, 0.37)
const WHITE := Color(0.9, 0.9, 0.86)
const YELLOW := Color(0.92, 0.72, 0.15)
const CENTRE: Array[String] = ["None", "Dashed", "Solid", "Double", "Double yellow"]
const BED := 0.2
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
	var m := new_model()
	m.setup(Vector3(half_all * 2.0 + spread * 2.0 + v * 4.0, BED + SURFACE + rise + v * 2.0, length), v)
	var top := BED + SURFACE
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
		m.fill_box(Vector3(c - half_road, y + BED, z), Vector3(c + half_road, y + top, z1), ASPHALT, 0.07, seed + 2)
		z = z1
	# Wear first, then the lines over it: paint only lands on asphalt that is still there, so
	# a tear or crack breaks a line, and the lines get their own chips after.
	_wear(m, p, rng, length, x_of, y_of, half_road, top, v, seed)
	z = -length / 2
	while z < length / 2 - 0.0001:
		var z1 := minf(z + v, length / 2)
		var mid := (z + z1) / 2
		_markings(m, p, float(x_of.call(mid)), z, z1, lanes, lane, half_road, float(y_of.call(mid)) + top, v)
		z = z1
	_chip_lines(m, p, rng, length, x_of, y_of, half_road, top, v)
	return m


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
func _wear(m: VoxelModel, p: Dictionary, rng: RandomNumberGenerator, length: float, x_of: Callable, y_of: Callable, half_road: float, top: float, v: float, seed: int) -> void:
	var wear: float = p["wear"]
	var surface := func(x_off: float, z: float) -> Vector3:
		return Vector3(float(x_of.call(z)) + x_off, top + float(y_of.call(z)), z)
	for i in int(wear * length * 0.6):
		var z := rng.randf_range(-length / 2, length / 2)
		var size := minf(rng.randf_range(0.4, 1.6), half_road * 0.8)
		var x_off := rng.randf_range(-half_road + size, half_road - size)
		m.paint_ellipsoid(surface.call(x_off, z), Vector3(size, v * 1.5, size * rng.randf_range(0.6, 1.8)), PATCH if rng.randf() < 0.6 else ASPHALT.darkened(0.25), 0.08, seed + i)
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
## along a wandering line, with cracks running off its ends.
func _tear(m: VoxelModel, p: Dictionary, rng: RandomNumberGenerator, surface: Callable, length: float, half_road: float, v: float) -> void:
	var size := float(p["tear_size"]) * rng.randf_range(0.6, 1.3)
	var width := clampf(size * rng.randf_range(0.25, 0.5), 0.2, half_road * 0.6)
	var z := rng.randf_range(-length / 2 + size, length / 2 - size)
	var x_off := rng.randf_range(-half_road + width, half_road - width)
	var heading := rng.randf() * TAU
	var bites := maxi(int(size / maxf(width * 0.6, v)), 2)
	var at := Vector2(x_off, z)
	var step := size / bites
	for b in bites:
		var r := width * rng.randf_range(0.6, 1.1)
		var centre: Vector3 = surface.call(at.x, at.y)
		m.carve_ellipsoid(centre, Vector3(r, SURFACE * 1.8, r * rng.randf_range(0.8, 1.6)))
		heading += rng.randf_range(-0.6, 0.6)
		at += Vector2(cos(heading), sin(heading)) * step
		at.x = clampf(at.x, -half_road + width, half_road - width)
	for end in [Vector2(x_off, z), at]:
		for c in rng.randi_range(1, 3):
			_crack(m, rng, surface, end.x, end.y, half_road, v, rng.randi_range(2, 5))


## Worn paint: small spots of bare asphalt across the road, which only show where they land
## on a line.
func _chip_lines(m: VoxelModel, p: Dictionary, rng: RandomNumberGenerator, length: float, x_of: Callable, y_of: Callable, half_road: float, top: float, v: float) -> void:
	var wear: float = p["wear"]
	for i in int(wear * length * half_road * 3.0):
		var z := rng.randf_range(-length / 2, length / 2)
		var x := float(x_of.call(z)) + rng.randf_range(-half_road, half_road)
		var r := rng.randf_range(0.04, 0.14)
		m.paint_ellipsoid(Vector3(x, top + float(y_of.call(z)), z), Vector3(r, v * 1.5, r * rng.randf_range(1.0, 3.0)), ASPHALT, 0.07, int(p["seed"]) + 900 + i)
