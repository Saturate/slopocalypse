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
		param("potholes", "Potholes", 0.0, 12.0, 1.0, 2.0),
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
	var m := VoxelModel.new()
	m.setup(Vector3(half_all * 2.0 + absf(bend) * 2.0 + v * 4.0, BED + SURFACE + v * 2.0, length), v)
	var top := BED + SURFACE
	# Row by row along the length, so the road can follow its curve.
	var z := -length / 2
	while z < length / 2 - 0.0001:
		var z1 := minf(z + v, length / 2)
		var c := _offset((z + z1) / 2, length, bend)
		m.fill_box(Vector3(c - half_all, 0, z), Vector3(c + half_all, BED, z1), GRAVEL, 0.22, seed)
		m.fill_box(Vector3(c - half_all, BED, z), Vector3(c - half_road, BED + SURFACE * 0.5, z1), GRAVEL, 0.22, seed + 1)
		m.fill_box(Vector3(c + half_road, BED, z), Vector3(c + half_all, BED + SURFACE * 0.5, z1), GRAVEL, 0.22, seed + 1)
		m.fill_box(Vector3(c - half_road, BED, z), Vector3(c + half_road, top, z1), ASPHALT, 0.07, seed + 2)
		_markings(m, p, c, z, z1, lanes, lane, half_road, top, v)
		z = z1
	_wear(m, p, rng, length, bend, half_road, top, v, seed)
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
	var mid := (z0 + z1) / 2
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


func _wear(m: VoxelModel, p: Dictionary, rng: RandomNumberGenerator, length: float, bend: float, half_road: float, top: float, v: float, seed: int) -> void:
	var wear: float = p["wear"]
	for i in int(wear * length * 0.6):
		var z := rng.randf_range(-length / 2, length / 2)
		var x := _offset(z, length, bend) + rng.randf_range(-half_road, half_road)
		var size := rng.randf_range(0.4, 1.6)
		m.paint_ellipsoid(Vector3(x, top, z), Vector3(size, v * 1.5, size * rng.randf_range(0.6, 1.8)), PATCH if rng.randf() < 0.6 else ASPHALT.darkened(0.25), 0.08, seed + i)
	# Cracks: short random walks carved one voxel deep.
	for i in int(wear * length * 0.4):
		var z := rng.randf_range(-length / 2, length / 2)
		var at := Vector3(_offset(z, length, bend) + rng.randf_range(-half_road, half_road) * 0.9, top, z)
		var heading := rng.randf() * TAU
		for s in rng.randi_range(3, 8):
			heading += rng.randf_range(-0.8, 0.8)
			var next := at + Vector3(cos(heading), 0, sin(heading)) * rng.randf_range(0.2, 0.5)
			m.carve_capsule(at + Vector3.UP * v * 0.5, next + Vector3.UP * v * 0.5, v * 0.5, v * 0.5)
			at = next
	for i in int(p["potholes"]):
		var z := rng.randf_range(-length / 2, length / 2)
		var x := _offset(z, length, bend) + rng.randf_range(-half_road, half_road) * 0.8
		var r := rng.randf_range(0.25, 0.6)
		m.carve_ellipsoid(Vector3(x, top, z), Vector3(r, SURFACE * 1.6, r * rng.randf_range(0.7, 1.3)))
