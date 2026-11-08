class_name VoxCar
extends VoxGenerator
## A homemade-looking utility car: a boxy cab-forward pickup with a hood, a glassed cab,
## an open bed, chunky bumpers, a roof rack and a spare wheel, weathered with rust and mud.
## Wheels are a separate model (`wheel()`), since they turn on their own.
##
## Local frame: nose towards +Z (cars drive along +Z), x across, y up from the ground the
## tyres stand on. Wheel arches are cut where `wheel_x`/`wheel_z` say.

const PAINTS: Array[String] = ["Rust red", "Army green", "Faded blue", "Sand", "Primer grey"]
const PAINT := [Color(0.55, 0.2, 0.13), Color(0.3, 0.36, 0.22), Color(0.3, 0.42, 0.52), Color(0.72, 0.62, 0.42), Color(0.5, 0.5, 0.48)]
const FRAME := Color(0.16, 0.16, 0.17)
const BUMPER := Color(0.22, 0.22, 0.23)
const GLASS := Color(0.42, 0.5, 0.55)
const HEADLIGHT := Color(0.95, 0.92, 0.75)
const TAILLIGHT := Color(0.75, 0.1, 0.08)
const GRILLE := Color(0.12, 0.12, 0.13)
const RUST := Color(0.42, 0.24, 0.12)
const MUD := Color(0.36, 0.29, 0.2)
const SEAT := Color(0.2, 0.17, 0.14)
const TYRE := Color(0.1, 0.1, 0.1)
const RIM := Color(0.55, 0.55, 0.53)
const HUB := Color(0.3, 0.3, 0.3)
## Body bottom above the ground, and the tops of the body sides and the cab.
const SILL := 0.45
const BELT := 1.12
const ROOF := 1.86


func title() -> String:
	return "Car"


func params() -> Array[Dictionary]:
	return [
		seed_param(),
		choice("paint", "Paint", PAINTS, 0),
		param("length", "Length (m)", 3.4, 5.0, 0.1, 4.2),
		param("width", "Width (m)", 1.6, 2.2, 0.05, 1.9),
		param("wheel_x", "Wheel track / 2 (m)", 0.6, 1.0, 0.01, 0.85),
		param("wheel_z", "Wheelbase / 2 (m)", 0.9, 1.8, 0.01, 1.35),
		param("wheel_radius", "Wheel radius (m)", 0.28, 0.5, 0.01, 0.38),
		param("wear", "Rust and mud", 0.0, 1.0, 0.05, 0.5),
		choice("rack", "Roof rack", ["No", "Yes"], 1),
		voxel_param(0.04, 0.15, 0.08),
	]


func build(values: Dictionary) -> VoxelModel:
	var p := with_defaults(values)
	var seed := int(p["seed"])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var l: float = p["length"]
	var w: float = p["width"]
	var v: float = p["voxel"]
	var paint: Color = PAINT[int(p["paint"])]
	var hl := l / 2.0
	var hw := w / 2.0
	var m := new_model()
	m.setup(Vector3(w + 0.6, ROOF + 0.5, l + 0.4), v)
	# Ladder frame, then the body tub with the arches cut out of it.
	m.fill_box(Vector3(-hw + 0.25, SILL - 0.1, -hl + 0.2), Vector3(hw - 0.25, SILL + 0.05, hl - 0.2), FRAME, 0.05, seed)
	m.fill_box(Vector3(-hw, SILL, -hl + 0.1), Vector3(hw, BELT, hl - 0.15), paint, 0.06, seed + 1)
	var cab_front := hl - 1.25
	var cab_back := cab_front - 1.55
	_hood(m, p, paint, cab_front, hl, seed)
	_cab(m, p, paint, cab_back, cab_front, seed)
	_bed(m, p, paint, -hl + 0.1, cab_back, seed)
	_arches(m, p)
	_bumpers(m, p, seed)
	_lights(m, p)
	if int(p["rack"]) == 1:
		_rack(m, p, cab_back, cab_front, seed)
	_wear(m, p, rng)
	return m


## The hood slopes down a little towards the grille.
func _hood(m: VoxelModel, p: Dictionary, paint: Color, z0: float, hl: float, seed: int) -> void:
	var hw := float(p["width"]) / 2.0 - 0.04
	var v: float = p["voxel"]
	var z := z0
	while z < hl - 0.15:
		var drop := (z - z0) / (hl - z0) * 0.12
		m.fill_box(Vector3(-hw, BELT - 0.02, z), Vector3(hw, BELT + 0.1 - drop, z + v), paint, 0.05, seed + 2)
		z += v
	# A bulge down the middle and seams either side of it.
	m.fill_box(Vector3(-0.3, BELT + 0.06, z0 + 0.1), Vector3(0.3, BELT + 0.14, hl - 0.4), paint.darkened(0.06), 0.05, seed + 3)
	for side: float in [-1.0, 1.0]:
		m.paint_box(Vector3(side * hw - 0.03, SILL + 0.1, z0), Vector3(side * hw + 0.03, BELT + 0.12, z0 + v), FRAME, 0.0, 0)


## Pillars, roof and glass all round, a door seam and handle each side, and seats inside.
func _cab(m: VoxelModel, p: Dictionary, paint: Color, z0: float, z1: float, seed: int) -> void:
	var hw := float(p["width"]) / 2.0 - 0.06
	var v: float = p["voxel"]
	var t := maxf(v, 0.08)
	m.fill_box(Vector3(-hw, BELT, z0), Vector3(hw, ROOF, z1), paint, 0.06, seed + 4)
	m.carve_box(Vector3(-hw + t, SILL + 0.1, z0 + t), Vector3(hw - t, ROOF - t, z1 - t))
	# A windscreen; the side and rear windows are open (it's that kind of car), so the
	# seats and whoever sits in them show.
	var low := BELT + 0.1
	var high := ROOF - 0.12
	m.fill_box(Vector3(-hw + 0.12, low, z1 - t), Vector3(hw - 0.12, high, z1), GLASS, 0.03, seed + 13)
	m.carve_box(Vector3(-hw + 0.15, low + 0.05, z0 - 0.01), Vector3(hw - 0.15, high, z0 + t + 0.01))
	var mid := (z0 + z1) / 2.0 + 0.1
	for side: float in [-1.0, 1.0]:
		var x0 := minf(side * (hw + 0.01), side * (hw - t - 0.01))
		var x1 := maxf(side * (hw + 0.01), side * (hw - t - 0.01))
		m.carve_box(Vector3(x0, low, mid + 0.08), Vector3(x1, high, z1 - 0.12))
		m.carve_box(Vector3(x0, low, z0 + 0.12), Vector3(x1, high, mid - 0.08))
		# Door seam and handle.
		var sx := side * (float(p["width"]) / 2.0)
		m.paint_box(Vector3(sx - 0.03, SILL + 0.05, mid - 0.05), Vector3(sx + 0.03, BELT + 0.05, mid + 0.03), paint.darkened(0.35), 0.0, 0)
		m.paint_box(Vector3(sx - 0.03, SILL + 0.05, z1 - 0.02), Vector3(sx + 0.03, BELT + 0.05, z1 + 0.05), paint.darkened(0.35), 0.0, 0)
		m.fill_box(Vector3(sx - 0.02 if side < 0.0 else sx, BELT - 0.2, mid + 0.15), Vector3(sx if side < 0.0 else sx + 0.02, BELT - 0.14, mid + 0.35), FRAME, 0.0, 0)
		# Seat: cushion and back.
		var cx := side * hw * 0.48
		m.fill_box(Vector3(cx - 0.25, SILL + 0.25, mid - 0.35), Vector3(cx + 0.25, SILL + 0.42, mid + 0.2), SEAT, 0.08, seed + 5)
		m.fill_box(Vector3(cx - 0.25, SILL + 0.42, mid - 0.45), Vector3(cx + 0.25, BELT + 0.35, mid - 0.32), SEAT, 0.08, seed + 5)
	# Steering wheel on the left (the driver's side: +X, facing +Z).
	m.fill_box(Vector3(hw * 0.48 - 0.18, BELT + 0.02, z1 - 0.45), Vector3(hw * 0.48 + 0.18, BELT + 0.08, z1 - 0.38), FRAME, 0.0, 0)
	m.fill_box(Vector3(-hw + t, SILL + 0.2, z1 - 0.35), Vector3(hw - t, BELT + 0.02, z1 - t), FRAME.lightened(0.1), 0.05, seed + 6)


## An open bed with a tailgate and a spare wheel lying in it.
func _bed(m: VoxelModel, p: Dictionary, paint: Color, z0: float, z1: float, seed: int) -> void:
	var hw := float(p["width"]) / 2.0
	var t := maxf(float(p["voxel"]), 0.08)
	m.carve_box(Vector3(-hw + t, SILL + 0.3, z0 + t), Vector3(hw - t, BELT + 0.01, z1))
	m.fill_box(Vector3(-hw + t, SILL + 0.22, z0 + t), Vector3(hw - t, SILL + 0.3, z1), FRAME.lightened(0.15), 0.08, seed + 7)
	m.paint_box(Vector3(-hw - 0.01, BELT - 0.08, z0 - 0.01), Vector3(hw + 0.01, BELT + 0.01, z0 + t + 0.01), paint.darkened(0.25), 0.05, seed + 8)
	var r := float(p["wheel_radius"]) * 0.95
	var at := Vector3(0.0, SILL + 0.3, (z0 + z1) / 2.0)
	m.fill_cylinder(at, r, 0.22, TYRE, 0.05, seed + 9)
	m.fill_cylinder(at + Vector3(0, 0.22, 0), r * 0.55, 0.02, RIM, 0.05, seed + 9)


## Round arches over each wheel, wide enough for the tyre to steer and bounce.
func _arches(m: VoxelModel, p: Dictionary) -> void:
	var wx: float = p["wheel_x"]
	var wz: float = p["wheel_z"]
	var r := float(p["wheel_radius"]) + 0.1
	var hw := float(p["width"]) / 2.0 + 0.2
	var cy := float(p["wheel_radius"])
	for z: float in [wz, -wz]:
		m.carve_capsule(Vector3(-hw, cy, z), Vector3(-wx + 0.25, cy, z), r, r)
		m.carve_capsule(Vector3(wx - 0.25, cy, z), Vector3(hw, cy, z), r, r)
		# Black inner lining so the arch doesn't show the paint through to the other side.
		for side: float in [-1.0, 1.0]:
			var x := side * (wx - 0.3)
			m.fill_box(Vector3(minf(x, x + side * 0.06), cy, z - r), Vector3(maxf(x, x + side * 0.06), cy + r, z + r), FRAME, 0.0, 0)


func _bumpers(m: VoxelModel, p: Dictionary, seed: int) -> void:
	var hl := float(p["length"]) / 2.0
	var hw := float(p["width"]) / 2.0
	m.fill_box(Vector3(-hw - 0.05, SILL - 0.05, hl - 0.2), Vector3(hw + 0.05, SILL + 0.25, hl + 0.1), BUMPER, 0.06, seed + 10)
	m.fill_box(Vector3(-hw - 0.05, SILL - 0.05, -hl - 0.1), Vector3(hw + 0.05, SILL + 0.2, -hl + 0.15), BUMPER, 0.06, seed + 11)
	# Grille bars between the headlights.
	var x := -hw + 0.4
	while x < hw - 0.4:
		m.fill_box(Vector3(x, SILL + 0.3, hl - 0.16), Vector3(x + 0.05, BELT - 0.05, hl - 0.1), GRILLE, 0.0, 0)
		x += 0.12


func _lights(m: VoxelModel, p: Dictionary) -> void:
	var hl := float(p["length"]) / 2.0
	var hw := float(p["width"]) / 2.0
	for side: float in [-1.0, 1.0]:
		var cx := side * (hw - 0.22)
		m.fill_box(Vector3(cx - 0.12, SILL + 0.38, hl - 0.18), Vector3(cx + 0.12, SILL + 0.62, hl - 0.06), HEADLIGHT, 0.0, 0)
		m.fill_box(Vector3(cx - 0.1, BELT - 0.25, -hl + 0.04), Vector3(cx + 0.1, BELT - 0.08, -hl + 0.12), TAILLIGHT, 0.0, 0)


func _rack(m: VoxelModel, p: Dictionary, z0: float, z1: float, seed: int) -> void:
	var hw := float(p["width"]) / 2.0 - 0.1
	for z: float in [z0 + 0.15, (z0 + z1) / 2.0, z1 - 0.15]:
		m.fill_box(Vector3(-hw, ROOF, z - 0.05), Vector3(hw, ROOF + 0.1, z + 0.05), FRAME, 0.0, 0)
	for side: float in [-1.0, 1.0]:
		m.fill_box(Vector3(side * hw - 0.05, ROOF + 0.1, z0 + 0.1), Vector3(side * hw + 0.05, ROOF + 0.24, z1 - 0.1), FRAME, 0.0, 0)
	# A jerrycan strapped on top.
	m.fill_box(Vector3(-0.5, ROOF + 0.06, z0 + 0.3), Vector3(-0.15, ROOF + 0.4, z0 + 0.55), Color(0.33, 0.4, 0.24), 0.05, seed + 12)


## Rust spots on the paint and mud up the sides from the wheels.
func _wear(m: VoxelModel, p: Dictionary, rng: RandomNumberGenerator) -> void:
	var wear: float = p["wear"]
	if wear <= 0.0:
		return
	var hl := float(p["length"]) / 2.0
	var hw := float(p["width"]) / 2.0
	for i in int(wear * 36.0):
		var at := Vector3(rng.randf_range(-hw, hw), rng.randf_range(SILL, ROOF), rng.randf_range(-hl, hl))
		var r := rng.randf_range(0.12, 0.35)
		m.paint_ellipsoid(at, Vector3(r, r * 0.7, r), RUST, 0.2, i)
	m.paint_box(Vector3(-hw - 0.1, 0.0, -hl - 0.2), Vector3(hw + 0.1, SILL + 0.4 * wear, hl + 0.2), MUD, 0.2, 99)
	# Splashes higher up behind each wheel.
	for z: float in [float(p["wheel_z"]), -float(p["wheel_z"])]:
		for side: float in [-1.0, 1.0]:
			m.paint_ellipsoid(Vector3(side * hw, SILL + 0.3, z - 0.5), Vector3(0.2, 0.35 * wear, 0.5), MUD, 0.25, 98)


## A wheel lying along x (its axle), centred on its origin.
static func wheel(radius: float, width: float, voxel: float = 0.04) -> VoxelModel:
	var m := new_model()
	m.setup(Vector3(radius * 2.0 + voxel * 4.0, width + voxel * 2.0, radius * 2.0 + voxel * 4.0), voxel)
	# Built standing on y, then turned by whoever shows it; tyre, sidewall ring, rim, hub.
	m.fill_cylinder(Vector3.ZERO, radius, width, TYRE, 0.08, 1)
	m.paint_ellipsoid(Vector3(0, width, 0), Vector3(radius * 0.85, voxel * 1.5, radius * 0.85), TYRE.lightened(0.08), 0.05, 2)
	m.fill_cylinder(Vector3(0, width * 0.2, 0), radius * 0.6, width * 0.82, RIM, 0.06, 3)
	m.fill_cylinder(Vector3(0, width * 0.2, 0), radius * 0.22, width * 0.88, HUB, 0.04, 4)
	return m
