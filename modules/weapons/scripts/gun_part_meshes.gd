class_name GunPartMeshes
extends RefCounted
## Meshes for gun parts, each in its own space with the origin at the point it mounts on
## (the receiver's origin is the gun's). Metres; guns point down -Z. Original designs:
## side profiles extruded for silhouettes, lofts for curves, toothed rails, open optic
## housings with glass. Built once at runtime and cached by mesh id.

const GUNMETAL := Color(0.2, 0.21, 0.23)
const LOWER := Color(0.25, 0.25, 0.26)
const DARK := Color(0.07, 0.07, 0.08)
const POLYMER := Color(0.13, 0.13, 0.14)
const FURNITURE := Color(0.5, 0.43, 0.31)
const RUBBER := Color(0.05, 0.05, 0.05)
const BRASS := Color(0.72, 0.56, 0.28)
const RETICLE := Color(1.0, 0.15, 0.1)
const GLASS := Color(0.75, 0.85, 0.88, 0.07)

## Picatinny-style teeth: one every this many metres along a rail.
const RAIL_PITCH := 0.01
const RAIL_WIDTH := 0.021
## Scope geometry the data's markers must match: bore axis height above the rail, and
## where the eyepiece's rear face is.
const SCOPE_AXIS_Y := 0.045
const SCOPE_EYEPIECE_Z := 0.135

static var _cache: Dictionary[String, ArrayMesh] = {}


## The mesh for `id` (a part's `mesh` field), or null if there is no such mesh.
static func mesh(id: String) -> ArrayMesh:
	if _cache.has(id):
		return _cache[id]
	var built: ArrayMesh = null
	match id:
		"receiver_ar": built = _receiver_ar()
		"barrel_14": built = _barrel(0.44)
		"barrel_10": built = _barrel(0.32)
		"handguard_std": built = _handguard(0.31, 5)
		"handguard_long": built = _handguard(0.36, 6)
		"stock_std": built = _stock_std()
		"stock_light": built = _stock_light()
		"grip_std": built = _grip_std()
		"mag_30": built = _magazine(8)
		"mag_45": built = _magazine(11)
		"muzzle_flash": built = _muzzle_flash()
		"muzzle_comp": built = _muzzle_comp()
		"muzzle_supp": built = _muzzle_supp()
		"optic_reddot": built = _optic_reddot()
		"optic_holo": built = _optic_holo()
		"optic_scope": built = _optic_scope()
		"pistol_frame": built = _pistol_frame()
		"slide_std": built = _slide(0.0, false)
		"slide_long": built = _slide(0.025, true)
		"pistol_mag_15": built = _pistol_mag(false)
		"pistol_mag_21": built = _pistol_mag(true)
		"pistol_comp": built = _pistol_comp()
		"pistol_supp": built = _pistol_supp()
		"optic_pistol_dot": built = _optic_pistol_dot()
		"launcher": built = _launcher()
	if built != null:
		_cache[id] = built
	return built


## Triangles in a mesh, for the detail budget.
static func triangles(m: Mesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		n += m.surface_get_array_len(s) / 3
	return n


static func _at(pos: Vector3, rot: Vector3 = Vector3.ZERO) -> Transform3D:
	return Transform3D(Basis.from_euler(rot), pos)


## Cylinders are built along Y; this lays one along -Z.
static func _along_z(pos: Vector3, spin: float = 0.0) -> Transform3D:
	return Transform3D(Basis.from_euler(Vector3(PI / 2.0, 0.0, 0.0)).rotated(Vector3.BACK, spin), pos)


## And this one across the gun, along X (pins, knobs).
static func _along_x(pos: Vector3) -> Transform3D:
	return Transform3D(Basis.from_euler(Vector3(0.0, 0.0, PI / 2.0)), pos)


## A mesh from up to four surfaces: metal, polymer, glowing reticle and glass. Pass null
## for any a part does not have.
static func _finish(metal: SurfaceTool, poly: SurfaceTool = null, glow: SurfaceTool = null, glass: SurfaceTool = null) -> ArrayMesh:
	var out := ArrayMesh.new()
	if metal != null:
		LowPoly.finish(metal, LowPoly.material(0.5, 0.35), out)
	if poly != null:
		LowPoly.finish(poly, LowPoly.material(0.8), out)
	if glow != null:
		var mat := LowPoly.material(0.3)
		mat.emission_enabled = true
		mat.emission = RETICLE
		mat.emission_energy_multiplier = 1.6
		LowPoly.finish(glow, mat, out)
	if glass != null:
		var g := LowPoly.material(0.05, 0.4)
		g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		g.vertex_color_use_as_albedo = false
		g.albedo_color = GLASS
		LowPoly.finish(glass, g, out)
	return out


## A rail along -Z from `z_back` to `z_front` whose base sits at height `y`: a base strip
## with a tooth every RAIL_PITCH, so optics clamp onto something that reads as a rail.
static func _rail(st: SurfaceTool, z_back: float, z_front: float, y: float) -> void:
	var length := z_back - z_front
	LowPoly.chamfer_box(st, Vector3(RAIL_WIDTH * 0.75, 0.0065, length), 0.0015, _at(Vector3(0, y + 0.003, (z_back + z_front) / 2.0)), DARK)
	var teeth := int(length / RAIL_PITCH)
	for i in teeth:
		var z := z_back - RAIL_PITCH * (i + 0.5)
		LowPoly.box(st, Vector3(RAIL_WIDTH, 0.004, RAIL_PITCH * 0.55), _at(Vector3(0, y + 0.008, z)), DARK)


static func _receiver_ar() -> ArrayMesh:
	var metal := LowPoly.begin()
	# Upper: a long box with a stepped rear where the charging handle sits.
	LowPoly.extrude(metal, PackedVector2Array([
		Vector2(-0.15, 0.03), Vector2(0.15, 0.03), Vector2(0.15, 0.06), Vector2(0.135, 0.07), Vector2(-0.15, 0.07),
	]), 0.058, Transform3D.IDENTITY, GUNMETAL)
	_rail(metal, 0.14, -0.15, 0.07)
	# Ejection port and dust cover on the right, forward assist behind it.
	LowPoly.box(metal, Vector3(0.002, 0.017, 0.052), _at(Vector3(0.0295, 0.05, -0.02)), DARK)
	LowPoly.box(metal, Vector3(0.002, 0.003, 0.056), _at(Vector3(0.0298, 0.0405, -0.02)), GUNMETAL)
	LowPoly.cylinder(metal, 0.0075, 0.03, 8, Transform3D(Basis.from_euler(Vector3(PI / 2.0, 0.0, 0.45)), Vector3(0.031, 0.056, 0.05)), GUNMETAL)
	LowPoly.chamfer_box(metal, Vector3(0.008, 0.012, 0.016), 0.002, _at(Vector3(0.031, 0.045, 0.045)), GUNMETAL)
	# Charging handle with its latch.
	LowPoly.chamfer_box(metal, Vector3(0.036, 0.007, 0.022), 0.002, _at(Vector3(0, 0.066, 0.156)), DARK)
	LowPoly.chamfer_box(metal, Vector3(0.012, 0.007, 0.012), 0.002, _at(Vector3(-0.022, 0.066, 0.16)), DARK)
	# Lower, a lighter alloy: magwell flaring down at the front, slimmer behind the grip.
	LowPoly.extrude(metal, PackedVector2Array([
		Vector2(-0.15, 0.031), Vector2(-0.15, 0.0), Vector2(-0.085, -0.004), Vector2(-0.083, -0.046),
		Vector2(0.004, -0.046), Vector2(0.006, -0.012), Vector2(0.12, -0.012), Vector2(0.15, 0.0), Vector2(0.15, 0.031),
	]), 0.054, Transform3D.IDENTITY, LOWER)
	# Magwell lip: a flared rim around the opening.
	LowPoly.chamfer_box(metal, Vector3(0.058, 0.007, 0.092), 0.002, _at(Vector3(0, -0.043, -0.04)), LOWER)
	LowPoly.box(metal, Vector3(0.036, 0.004, 0.072), _at(Vector3(0, -0.0475, -0.04)), DARK)
	# Pins, magazine release, selector, bolt catch.
	for z in [-0.135, 0.125]:
		LowPoly.cylinder(metal, 0.0045, 0.058, 8, _along_x(Vector3(0, 0.02, z)), DARK)
	LowPoly.cylinder(metal, 0.006, 0.058, 8, _along_x(Vector3(0, -0.02, 0.0)), DARK)
	LowPoly.chamfer_box(metal, Vector3(0.004, 0.006, 0.02), 0.001, _at(Vector3(-0.029, 0.01, 0.07), Vector3(-0.5, 0, 0)), DARK)
	LowPoly.chamfer_box(metal, Vector3(0.004, 0.016, 0.01), 0.001, _at(Vector3(-0.029, 0.012, -0.002)), DARK)
	var poly := LowPoly.begin()
	# Trigger guard: a closed loop under the lower, with the trigger inside it.
	LowPoly.chamfer_box(poly, Vector3(0.012, 0.006, 0.075), 0.002, _at(Vector3(0, -0.047, 0.065)), POLYMER)
	LowPoly.chamfer_box(poly, Vector3(0.012, 0.04, 0.007), 0.002, _at(Vector3(0, -0.03, 0.03)), POLYMER)
	LowPoly.extrude(poly, PackedVector2Array([
		Vector2(0.05, -0.012), Vector2(0.056, -0.012), Vector2(0.06, -0.025), Vector2(0.058, -0.038), Vector2(0.053, -0.04), Vector2(0.054, -0.026),
	]), 0.005, Transform3D.IDENTITY, DARK)
	return _finish(metal, poly)


## A stepped barrel: thick at the chamber, slimmer forward, with a gas block that hides
## under the handguard.
static func _barrel(length: float) -> ArrayMesh:
	var metal := LowPoly.begin()
	LowPoly.cylinder(metal, 0.016, 0.08, 12, _along_z(Vector3(0, 0, -0.04)), DARK)
	LowPoly.cylinder(metal, 0.0125, length - 0.08, 12, _along_z(Vector3(0, 0, -0.08 - (length - 0.08) / 2.0)), DARK)
	LowPoly.chamfer_box(metal, Vector3(0.026, 0.03, 0.026), 0.004, _at(Vector3(0, 0.004, -0.2)), GUNMETAL)
	# Threads at the muzzle, where devices screw on.
	for i in 3:
		LowPoly.cylinder(metal, 0.0133, 0.003, 12, _along_z(Vector3(0, 0, -length + 0.004 + i * 0.006)), GUNMETAL)
	return _finish(metal)


## An eight-sided free-float tube the barrel shows through, toothed rail on top, slots on
## the sides and bottom, a folding front sight at the far end.
static func _handguard(length: float, slots: int) -> ArrayMesh:
	var metal := LowPoly.begin()
	var mid := Vector3(0, 0.005, -length / 2.0)
	LowPoly.tube(metal, 0.034, 0.029, length, 8, _along_z(mid, PI / 8.0), GUNMETAL)
	# Thicker end caps make the tube read as one machined part.
	LowPoly.tube(metal, 0.0355, 0.028, 0.012, 8, _along_z(Vector3(0, 0.005, -length + 0.006), PI / 8.0), DARK)
	LowPoly.tube(metal, 0.0355, 0.028, 0.01, 8, _along_z(Vector3(0, 0.005, -0.005), PI / 8.0), GUNMETAL)
	var flat := 0.034 * cos(PI / 8.0)
	var top := 0.005 + flat
	# Level with the receiver's rail, so the two read as one.
	_rail(metal, -0.002, -length + 0.004, top - 0.001)
	for i in slots:
		var z := -0.05 - i * (length - 0.08) / maxf(1.0, slots - 1.0)
		for side in [-1.0, 1.0]:
			LowPoly.box(metal, Vector3(0.002, 0.008, 0.024), _at(Vector3(side * (flat + 0.0005), 0.005, z)), DARK)
			# The diagonal faces carry slots too: thin axis along the face normal.
			var normal := Vector3(side * 0.7071, -0.7071, 0.0)
			LowPoly.box(metal, Vector3(0.002, 0.008, 0.024), Transform3D(Basis(Vector3.BACK, -side * PI / 4.0), Vector3(0, 0.005, z) + normal * (flat + 0.0005)), DARK)
		LowPoly.box(metal, Vector3(0.008, 0.002, 0.024), _at(Vector3(0, 0.005 - flat - 0.0005, z)), DARK)
	# Folding front sight standing on the rail's front end.
	var y0 := top + 0.009
	LowPoly.chamfer_box(metal, Vector3(0.02, 0.008, 0.02), 0.002, _at(Vector3(0, y0 + 0.004, -length + 0.02)), DARK)
	LowPoly.chamfer_box(metal, Vector3(0.016, 0.022, 0.006), 0.0015, _at(Vector3(0, y0 + 0.018, -length + 0.02)), DARK)
	LowPoly.box(metal, Vector3(0.003, 0.01, 0.003), _at(Vector3(0, y0 + 0.032, -length + 0.02)), DARK)
	return _finish(metal)


static func _stock_std() -> ArrayMesh:
	var metal := LowPoly.begin()
	LowPoly.cylinder(metal, 0.0145, 0.11, 12, _along_z(Vector3(0, 0, 0.055)), DARK)
	var poly := LowPoly.begin()
	# A slim nose over the tube widening into the butt; the comb stays low so it keeps out
	# of the sight picture when aiming.
	LowPoly.extrude(poly, PackedVector2Array([
		Vector2(0.035, 0.018), Vector2(0.12, 0.02), Vector2(0.12, -0.03), Vector2(0.09, -0.024), Vector2(0.035, -0.019),
	]), 0.034, Transform3D.IDENTITY, FURNITURE)
	LowPoly.extrude(poly, PackedVector2Array([
		Vector2(0.115, 0.021), Vector2(0.172, 0.024), Vector2(0.2, 0.024), Vector2(0.202, -0.086),
		Vector2(0.182, -0.09), Vector2(0.14, -0.05), Vector2(0.115, -0.033),
	]), 0.044, Transform3D.IDENTITY, FURNITURE)
	# Bevel strips soften the top edges; a dark sling cut-out breaks up the flank.
	for side in [-1.0, 1.0]:
		LowPoly.box(poly, Vector3(0.006, 0.006, 0.085), Transform3D(Basis(Vector3.BACK, side * PI / 4.0), Vector3(side * 0.02, 0.022, 0.158)), FURNITURE.darkened(0.08))
		LowPoly.box(poly, Vector3(0.002, 0.01, 0.045), _at(Vector3(side * 0.0222, -0.045, 0.165)), DARK)
	LowPoly.extrude(poly, PackedVector2Array([
		Vector2(0.2, 0.026), Vector2(0.215, 0.026), Vector2(0.217, -0.09), Vector2(0.202, -0.09),
	]), 0.048, Transform3D.IDENTITY, RUBBER)
	return _finish(metal, poly)


## Skeleton stock: the buffer tube, a bent top bar and a strut to a slim butt plate.
static func _stock_light() -> ArrayMesh:
	var metal := LowPoly.begin()
	LowPoly.cylinder(metal, 0.0145, 0.17, 12, _along_z(Vector3(0, 0, 0.085)), DARK)
	LowPoly.cylinder(metal, 0.016, 0.012, 12, _along_z(Vector3(0, 0, 0.006)), GUNMETAL)
	var rings: Array[Transform3D] = []
	for i in 5:
		var t := float(i) / 4.0
		rings.append(Transform3D(Basis(Vector3.RIGHT, -0.12 * t), Vector3(0, 0.017 - 0.004 * t, 0.06 + 0.11 * t)))
	LowPoly.loft(metal, rings, Vector2(0.006, 0.004), GUNMETAL)
	var strut_from := Vector3(0, -0.012, 0.075)
	var strut := Vector3(0, -0.075, 0.172) - strut_from
	LowPoly.cylinder(metal, 0.006, strut.length(), 6, Transform3D(Basis(Quaternion(Vector3.UP, strut.normalized())), strut_from + strut / 2.0), GUNMETAL)
	var poly := LowPoly.begin()
	LowPoly.extrude(poly, PackedVector2Array([
		Vector2(0.165, 0.028), Vector2(0.185, 0.028), Vector2(0.188, -0.09), Vector2(0.168, -0.088),
	]), 0.04, Transform3D.IDENTITY, POLYMER)
	LowPoly.extrude(poly, PackedVector2Array([
		Vector2(0.185, 0.028), Vector2(0.193, 0.028), Vector2(0.196, -0.09), Vector2(0.188, -0.09),
	]), 0.042, Transform3D.IDENTITY, RUBBER)
	return _finish(metal, poly)


## Raked pistol grip with finger bumps down the front and a flared base.
static func _grip_std() -> ArrayMesh:
	var poly := LowPoly.begin()
	LowPoly.extrude(poly, PackedVector2Array([
		Vector2(-0.026, 0.03), Vector2(0.028, 0.03), Vector2(0.05, -0.09), Vector2(0.046, -0.104),
		Vector2(0.0, -0.104), Vector2(-0.004, -0.096), Vector2(-0.004, -0.084), Vector2(-0.01, -0.07),
		Vector2(-0.008, -0.058), Vector2(-0.015, -0.043), Vector2(-0.013, -0.03), Vector2(-0.02, -0.015),
	]), 0.03, Transform3D.IDENTITY, FURNITURE)
	# Raised grip strips on both sides, following the rake.
	for side in [-1.0, 1.0]:
		for k in 4:
			var y := -0.025 - k * 0.017
			LowPoly.chamfer_box(poly, Vector3(0.003, 0.006, 0.03), 0.001, _at(Vector3(side * 0.0155, y, 0.012 - y * 0.25), Vector3(-0.25, 0, 0)), POLYMER)
	LowPoly.chamfer_box(poly, Vector3(0.034, 0.006, 0.05), 0.002, _at(Vector3(0, -0.104, 0.024)), POLYMER)
	return _finish(null, poly)


## A curved box magazine lofted down and forward, ribbed sides, a floor plate and the top
## round showing in the feed lips. `segments` sets the length.
static func _magazine(segments: int) -> ArrayMesh:
	var poly := LowPoly.begin()
	var metal := LowPoly.begin()
	var step := 0.024
	# Section X is width, section Y front to back, the path runs down and curves forward.
	var basis := Basis(Vector3.RIGHT, Vector3(0, 0, 1), Vector3.DOWN).rotated(Vector3.RIGHT, 0.08)
	var pos := Vector3(0, 0.012, 0.0)
	var rings: Array[Transform3D] = []
	for i in segments + 1:
		rings.append(Transform3D(basis, pos))
		pos += basis.z * step
		basis = basis.rotated(Vector3.RIGHT, 0.032)
	LowPoly.loft(poly, rings, Vector2(0.0165, 0.032), FURNITURE)
	# Two ridges down each side follow the curve.
	for i in range(1, segments):
		var r := rings[i]
		for side in [-1.0, 1.0]:
			for along in [-0.014, 0.014]:
				LowPoly.box(poly, Vector3(0.002, 0.006, step * 1.02), Transform3D(r.basis, r.origin + r.basis.x * side * 0.0172 + r.basis.y * along + r.basis.z * step / 2.0), FURNITURE.darkened(0.15))
	# Stiffening ribs across the upper body.
	for i in [2, 3]:
		var r := rings[i]
		LowPoly.chamfer_box(poly, Vector3(0.037, 0.068, 0.006), 0.0015, Transform3D(r.basis * Basis(Vector3.RIGHT, -PI / 2.0), r.origin), FURNITURE.darkened(0.1))
	var bottom := rings[rings.size() - 1]
	LowPoly.chamfer_box(poly, Vector3(0.044, 0.012, 0.08), 0.003, Transform3D(bottom.basis * Basis(Vector3.RIGHT, -PI / 2.0), bottom.origin + bottom.basis.z * 0.004), POLYMER)
	LowPoly.cylinder(metal, 0.005, 0.03, 8, _along_z(Vector3(0, 0.016, -0.004)), BRASS)
	return _finish(metal, poly)


static func _muzzle_flash() -> ArrayMesh:
	var metal := LowPoly.begin()
	LowPoly.cylinder(metal, 0.0155, 0.024, 12, _along_z(Vector3(0, 0, -0.012)), GUNMETAL)
	# Four prongs with open slots between them.
	for i in 4:
		var a := TAU * (i + 0.5) / 4.0
		LowPoly.chamfer_box(metal, Vector3(0.011, 0.005, 0.038), 0.0015, Transform3D(Basis(Vector3.BACK, a + PI / 2.0), Vector3(cos(a) * 0.0125, sin(a) * 0.0125, -0.043)), GUNMETAL)
	return _finish(metal)


static func _muzzle_comp() -> ArrayMesh:
	var metal := LowPoly.begin()
	LowPoly.chamfer_box(metal, Vector3(0.03, 0.03, 0.065), 0.006, _at(Vector3(0, 0, -0.0325)), GUNMETAL)
	# Side baffles and top ports vent gas sideways and up, which holds the muzzle down.
	for i in 3:
		for side in [-1.0, 1.0]:
			LowPoly.box(metal, Vector3(0.002, 0.018, 0.009), _at(Vector3(side * 0.0151, 0, -0.016 - i * 0.017)), DARK)
		LowPoly.box(metal, Vector3(0.016, 0.002, 0.007), _at(Vector3(0, 0.0151, -0.016 - i * 0.017)), DARK)
	LowPoly.cylinder(metal, 0.006, 0.002, 12, _along_z(Vector3(0, 0, -0.0655)), DARK)
	return _finish(metal)


static func _muzzle_supp() -> ArrayMesh:
	var metal := LowPoly.begin()
	LowPoly.cylinder(metal, 0.016, 0.02, 16, _along_z(Vector3(0, 0, -0.01)), GUNMETAL, 0.022)
	LowPoly.cylinder(metal, 0.022, 0.13, 16, _along_z(Vector3(0, 0, -0.085)), DARK)
	LowPoly.cylinder(metal, 0.022, 0.02, 16, _along_z(Vector3(0, 0, -0.16)), GUNMETAL, 0.017)
	# Grip rings for screwing it on, and the bore at the front.
	for z in [-0.028, -0.034, -0.04]:
		LowPoly.cylinder(metal, 0.0228, 0.003, 16, _along_z(Vector3(0, 0, z)), GUNMETAL)
	LowPoly.cylinder(metal, 0.0065, 0.002, 12, _along_z(Vector3(0, 0, -0.1705)), RUBBER)
	return _finish(metal)


## Rail clamp shared by the optics: a base block with a cross bolt and a knob on the left.
static func _clamp(st: SurfaceTool, length: float, z: float) -> void:
	# Reaches a little below the mount so it sits down on the rail's teeth.
	LowPoly.chamfer_box(st, Vector3(0.03, 0.012, length), 0.003, _at(Vector3(0, 0.004, z)), DARK)
	LowPoly.cylinder(st, 0.006, 0.006, 10, _along_x(Vector3(-0.018, 0.006, z)), DARK)
	LowPoly.cylinder(st, 0.003, 0.034, 8, _along_x(Vector3(0, 0.004, z)), GUNMETAL)


## Red dot: an open tube to look through, the dot just behind a tinted front lens, turrets
## on top and right.
static func _optic_reddot() -> ArrayMesh:
	var metal := LowPoly.begin()
	_clamp(metal, 0.04, 0.0)
	LowPoly.chamfer_box(metal, Vector3(0.016, 0.014, 0.03), 0.003, _at(Vector3(0, 0.018, 0.0)), DARK)
	LowPoly.tube(metal, 0.022, 0.0195, 0.066, 20, _along_z(Vector3(0, 0.036, 0.0)), DARK)
	# A ring at each end gives the lens a bezel.
	for z in [-0.032, 0.032]:
		LowPoly.tube(metal, 0.0235, 0.0195, 0.006, 20, _along_z(Vector3(0, 0.036, z)), GUNMETAL)
	LowPoly.cylinder(metal, 0.007, 0.01, 10, Transform3D(Basis.IDENTITY, Vector3(0, 0.062, 0.002)), GUNMETAL)
	LowPoly.cylinder(metal, 0.007, 0.01, 10, _along_x(Vector3(0.026, 0.036, 0.002)), GUNMETAL)
	var glow := LowPoly.begin()
	LowPoly.chamfer_box(glow, Vector3(0.0055, 0.0055, 0.002), 0.001, _at(Vector3(0, 0.036, -0.0245)), RETICLE)
	var glass := LowPoly.begin()
	LowPoly.cylinder(glass, 0.0196, 0.001, 20, _along_z(Vector3(0, 0.036, -0.029)), GLASS)
	return _finish(metal, null, glow, glass)


## Holo sight: a square window under a hood on a long base, buttons at the back, a
## battery cap on the side, ring-and-dot reticle seen through the glass.
static func _optic_holo() -> ArrayMesh:
	var metal := LowPoly.begin()
	_clamp(metal, 0.06, 0.005)
	LowPoly.chamfer_box(metal, Vector3(0.036, 0.01, 0.078), 0.003, _at(Vector3(0, 0.014, 0.005)), DARK)
	# Posts at the corners instead of solid walls, so it reads as an open window from the side.
	for x in [-0.024, 0.024]:
		for z in [-0.027, 0.015]:
			LowPoly.chamfer_box(metal, Vector3(0.006, 0.046, 0.009), 0.002, _at(Vector3(x, 0.035, z)), DARK)
	LowPoly.chamfer_box(metal, Vector3(0.054, 0.006, 0.056), 0.002, _at(Vector3(0, 0.06, -0.006)), DARK)
	LowPoly.chamfer_box(metal, Vector3(0.03, 0.012, 0.022), 0.003, _at(Vector3(0, 0.024, 0.032)), DARK)
	for x in [-0.007, 0.007]:
		LowPoly.chamfer_box(metal, Vector3(0.008, 0.005, 0.004), 0.001, _at(Vector3(x, 0.024, 0.044)), GUNMETAL)
	LowPoly.cylinder(metal, 0.008, 0.012, 10, _along_x(Vector3(0.022, 0.02, 0.022)), GUNMETAL)
	var glow := LowPoly.begin()
	LowPoly.tube(glow, 0.009, 0.0075, 0.001, 16, _along_z(Vector3(0, 0.034, -0.02)), RETICLE)
	LowPoly.chamfer_box(glow, Vector3(0.002, 0.002, 0.001), 0.0004, _at(Vector3(0, 0.034, -0.02)), RETICLE)
	var glass := LowPoly.begin()
	LowPoly.box(glass, Vector3(0.042, 0.04, 0.0015), _at(Vector3(0, 0.035, -0.026)), GLASS)
	return _finish(metal, null, glow, glass)


## A fixed-power scope on two rings: objective bell in front, eyepiece behind, turrets on
## top and right. The eyepiece is left dark; the scope view draws the magnified picture on
## a lens there (see ScopeView), so the mesh only frames it.
static func _optic_scope() -> ArrayMesh:
	var metal := LowPoly.begin()
	var axis := SCOPE_AXIS_Y
	for z in [-0.035, 0.045]:
		_clamp(metal, 0.022, z)
		LowPoly.chamfer_box(metal, Vector3(0.012, axis - 0.012, 0.016), 0.002, _at(Vector3(0, (axis + 0.004) / 2.0, z)), DARK)
		LowPoly.tube(metal, 0.0165, 0.0127, 0.016, 16, _along_z(Vector3(0, axis, z)), DARK)
	LowPoly.cylinder(metal, 0.0127, 0.16, 16, _along_z(Vector3(0, axis, 0.0)), GUNMETAL)
	# Objective: a cone out to the bell, then the bell itself, open at the front.
	LowPoly.cylinder(metal, 0.0127, 0.035, 16, _along_z(Vector3(0, axis, -0.0975)), GUNMETAL, 0.021)
	LowPoly.tube(metal, 0.022, 0.0195, 0.05, 20, _along_z(Vector3(0, axis, -0.14)), GUNMETAL)
	LowPoly.tube(metal, 0.0228, 0.0195, 0.006, 20, _along_z(Vector3(0, axis, -0.163)), DARK)
	# Eyepiece: a short cone and a rubber eyecup.
	LowPoly.cylinder(metal, 0.0127, 0.02, 16, _along_z(Vector3(0, axis, 0.09)), GUNMETAL, 0.023)
	# Dark inside, so its inner wall never shows as a bright ring around the picture.
	LowPoly.tube(metal, 0.0235, 0.021, 0.035, 24, _along_z(Vector3(0, axis, SCOPE_EYEPIECE_Z - 0.0175)), RUBBER)
	LowPoly.tube(metal, 0.024, 0.021, 0.008, 24, _along_z(Vector3(0, axis, SCOPE_EYEPIECE_Z - 0.004)), RUBBER)
	# Turrets: elevation on top, windage on the right, with caps.
	LowPoly.cylinder(metal, 0.009, 0.016, 12, Transform3D(Basis.IDENTITY, Vector3(0, axis + 0.018, 0.005)), GUNMETAL)
	LowPoly.cylinder(metal, 0.0095, 0.005, 12, Transform3D(Basis.IDENTITY, Vector3(0, axis + 0.026, 0.005)), DARK)
	LowPoly.cylinder(metal, 0.009, 0.016, 12, _along_x(Vector3(0.018, axis, 0.005)), GUNMETAL)
	LowPoly.cylinder(metal, 0.0095, 0.005, 12, _along_x(Vector3(0.026, axis, 0.005)), DARK)
	LowPoly.chamfer_box(metal, Vector3(0.026, 0.026, 0.022), 0.004, _at(Vector3(0, axis, 0.005)), GUNMETAL)
	# Behind the lens, so the tube never shows through where the picture is not drawn.
	LowPoly.cylinder(metal, 0.0211, 0.002, 24, _along_z(Vector3(0, axis, SCOPE_EYEPIECE_Z - 0.012)), RUBBER)
	var glass := LowPoly.begin()
	LowPoly.cylinder(glass, 0.0196, 0.001, 20, _along_z(Vector3(0, axis, -0.16)), GLASS)
	return _finish(metal, null, null, glass)


## Polymer pistol frame: dust cover, raked grip with a beavertail, trigger guard, a short
## accessory rail underneath. The slide sits on top (y 0 up); the grip runs down and back.
static func _pistol_frame() -> ArrayMesh:
	var poly := LowPoly.begin()
	LowPoly.extrude(poly, PackedVector2Array([
		Vector2(-0.095, 0.0), Vector2(0.062, 0.0), Vector2(0.066, -0.014), Vector2(0.074, -0.026),
		Vector2(0.062, -0.03), Vector2(0.082, -0.112), Vector2(0.076, -0.121), Vector2(0.03, -0.121),
		Vector2(0.026, -0.11), Vector2(0.012, -0.046), Vector2(0.006, -0.036), Vector2(-0.002, -0.017),
		Vector2(-0.095, -0.017),
	]), 0.028, Transform3D.IDENTITY, POLYMER)
	# Trigger guard and trigger.
	LowPoly.chamfer_box(poly, Vector3(0.012, 0.005, 0.05), 0.0015, _at(Vector3(0, -0.043, -0.02)), POLYMER)
	LowPoly.chamfer_box(poly, Vector3(0.012, 0.03, 0.006), 0.0015, _at(Vector3(0, -0.03, -0.044), Vector3(0.2, 0, 0)), POLYMER)
	LowPoly.chamfer_box(poly, Vector3(0.005, 0.02, 0.005), 0.001, _at(Vector3(0, -0.027, -0.006), Vector3(-0.3, 0, 0)), DARK)
	# Grip texture strips following the rake, a slide stop and the magazine release.
	for side in [-1.0, 1.0]:
		for k in 4:
			var y := -0.05 - k * 0.017
			LowPoly.box(poly, Vector3(0.002, 0.007, 0.03), _at(Vector3(side * 0.0145, y, 0.045 - (y + 0.05) * 0.3), Vector3(-0.3, 0, 0)), POLYMER.darkened(0.3))
	LowPoly.box(poly, Vector3(0.003, 0.004, 0.02), _at(Vector3(-0.0152, -0.006, -0.015)), DARK)
	LowPoly.cylinder(poly, 0.004, 0.03, 8, _along_x(Vector3(0, -0.026, 0.012)), DARK)
	# Accessory rail under the dust cover, teeth facing down.
	for i in 4:
		LowPoly.box(poly, Vector3(0.022, 0.004, 0.006), _at(Vector3(0, -0.019, -0.088 + i * 0.012)), POLYMER.darkened(0.2))
	return _finish(null, poly)


## Pistol slide: serrations at the back, ejection port, iron sights, the barrel's crown at
## the front. `extra` makes it longer; `threaded` adds a barrel sticking out for a muzzle
## device.
static func _slide(extra: float, threaded: bool) -> ArrayMesh:
	var metal := LowPoly.begin()
	var front := -0.1 - extra
	LowPoly.extrude(metal, PackedVector2Array([
		Vector2(front, 0.0), Vector2(0.065, 0.0), Vector2(0.065, 0.026), Vector2(0.058, 0.032),
		Vector2(front + 0.006, 0.032), Vector2(front, 0.026),
	]), 0.026, Transform3D.IDENTITY, GUNMETAL)
	for side in [-1.0, 1.0]:
		for k in 5:
			LowPoly.box(metal, Vector3(0.002, 0.02, 0.003), _at(Vector3(side * 0.0131, 0.016, 0.034 + k * 0.006)), DARK)
	LowPoly.box(metal, Vector3(0.002, 0.01, 0.032), _at(Vector3(0.0131, 0.024, -0.012)), DARK)
	LowPoly.chamfer_box(metal, Vector3(0.014, 0.004, 0.03), 0.001, _at(Vector3(0.0, 0.033, -0.012)), DARK)
	# Rear sight: two posts with a notch between; front post.
	for x in [-0.006, 0.006]:
		LowPoly.box(metal, Vector3(0.006, 0.007, 0.008), _at(Vector3(x, 0.0355, 0.058)), DARK)
	LowPoly.box(metal, Vector3(0.004, 0.007, 0.006), _at(Vector3(0, 0.0355, front + 0.012)), DARK)
	if threaded:
		LowPoly.cylinder(metal, 0.0068, 0.04, 10, _along_z(Vector3(0, 0.016, front - 0.004)), DARK)
		for i in 3:
			LowPoly.cylinder(metal, 0.0072, 0.002, 10, _along_z(Vector3(0, 0.016, front - 0.012 - i * 0.005)), GUNMETAL)
	else:
		LowPoly.cylinder(metal, 0.0068, 0.004, 10, _along_z(Vector3(0, 0.016, front - 0.001)), DARK)
	return _finish(metal)


## Only the baseplate shows below the grip; the extended one adds a sleeve.
static func _pistol_mag(extended: bool) -> ArrayMesh:
	var poly := LowPoly.begin()
	var drop := 0.03 if extended else 0.0
	if extended:
		LowPoly.chamfer_box(poly, Vector3(0.026, drop + 0.004, 0.034), 0.002, _at(Vector3(0, -drop / 2.0, 0.003), Vector3(-0.3, 0, 0)), POLYMER)
	LowPoly.chamfer_box(poly, Vector3(0.03, 0.008, 0.038), 0.002, _at(Vector3(0, -drop - 0.003, 0.004 + drop * 0.3), Vector3(-0.3, 0, 0)), DARK)
	return _finish(null, poly)


## A rocket launcher: a long olive tube with a flared back end, a grip and a front grip, and a
## sight block on the left of the tube.
static func _launcher() -> ArrayMesh:
	var olive := Color(0.3, 0.33, 0.22)
	var band := Color(0.62, 0.52, 0.18)
	var metal := LowPoly.begin()
	var poly := LowPoly.begin()
	# The tube, with reinforcing rings along it and a band near the front.
	LowPoly.tube(metal, 0.06, 0.05, 1.0, 24, _along_z(Vector3(0, 0, -0.15)), olive)
	for z: float in [-0.5, -0.32, 0.02, 0.22]:
		LowPoly.tube(metal, 0.066, 0.058, 0.025, 24, _along_z(Vector3(0, 0, z)), GUNMETAL)
	LowPoly.tube(metal, 0.0615, 0.058, 0.04, 24, _along_z(Vector3(0, 0, -0.42)), band)
	# Muzzle rim and the flared back end.
	LowPoly.tube(metal, 0.07, 0.05, 0.05, 24, _along_z(Vector3(0, 0, -0.64)), GUNMETAL)
	LowPoly.cylinder(metal, 0.062, 0.14, 24, _along_z(Vector3(0, 0, 0.42)), GUNMETAL, 0.09)
	LowPoly.tube(metal, 0.092, 0.084, 0.02, 24, _along_z(Vector3(0, 0, 0.49)), DARK)
	# Grip, trigger and guard, front grip.
	LowPoly.chamfer_box(poly, Vector3(0.032, 0.11, 0.045), 0.006, _at(Vector3(0, -0.115, 0.12), Vector3(deg_to_rad(-12.0), 0, 0)), POLYMER)
	LowPoly.box(metal, Vector3(0.008, 0.03, 0.012), _at(Vector3(0, -0.075, 0.075)), DARK)
	LowPoly.box(metal, Vector3(0.012, 0.006, 0.07), _at(Vector3(0, -0.1, 0.07)), GUNMETAL)
	LowPoly.box(metal, Vector3(0.012, 0.04, 0.006), _at(Vector3(0, -0.08, 0.035)), GUNMETAL)
	LowPoly.chamfer_box(poly, Vector3(0.03, 0.085, 0.04), 0.006, _at(Vector3(0, -0.1, -0.2)), POLYMER)
	# Shoulder rest under the back.
	LowPoly.chamfer_box(poly, Vector3(0.05, 0.035, 0.16), 0.008, _at(Vector3(0, -0.075, 0.3)), RUBBER)
	# Sight block on the left with a rear aperture and a front post.
	LowPoly.chamfer_box(metal, Vector3(0.03, 0.045, 0.09), 0.005, _at(Vector3(-0.075, 0.03, -0.02)), DARK)
	LowPoly.tube(metal, 0.012, 0.007, 0.01, 12, _along_z(Vector3(-0.075, 0.065, 0.02)), DARK)
	LowPoly.box(metal, Vector3(0.004, 0.03, 0.004), _at(Vector3(-0.075, 0.07, -0.06)), DARK)
	# Sling mounts.
	for z: float in [-0.5, 0.3]:
		LowPoly.tube(metal, 0.012, 0.008, 0.006, 10, _at(Vector3(0.068, 0, z), Vector3(0, 0, PI / 2.0)), GUNMETAL)
	return _finish(metal, poly)


static func _pistol_comp() -> ArrayMesh:
	var metal := LowPoly.begin()
	LowPoly.chamfer_box(metal, Vector3(0.026, 0.026, 0.034), 0.004, _at(Vector3(0, 0, -0.017)), GUNMETAL)
	for i in 2:
		LowPoly.box(metal, Vector3(0.014, 0.002, 0.006), _at(Vector3(0, 0.0131, -0.01 - i * 0.012)), DARK)
	LowPoly.cylinder(metal, 0.005, 0.002, 10, _along_z(Vector3(0, 0, -0.0345)), DARK)
	return _finish(metal)


static func _pistol_supp() -> ArrayMesh:
	var metal := LowPoly.begin()
	LowPoly.cylinder(metal, 0.016, 0.13, 14, _along_z(Vector3(0, 0, -0.07)), DARK)
	LowPoly.cylinder(metal, 0.0165, 0.01, 14, _along_z(Vector3(0, 0, -0.008)), GUNMETAL)
	LowPoly.cylinder(metal, 0.005, 0.002, 10, _along_z(Vector3(0, 0, -0.1355)), RUBBER)
	return _finish(metal)


## Mini red dot for a slide: a low base, an open window frame with glass, the dot.
static func _optic_pistol_dot() -> ArrayMesh:
	var metal := LowPoly.begin()
	LowPoly.chamfer_box(metal, Vector3(0.024, 0.008, 0.032), 0.002, _at(Vector3(0, 0.004, 0.0)), DARK)
	for x in [-0.0105, 0.0105]:
		LowPoly.chamfer_box(metal, Vector3(0.003, 0.02, 0.006), 0.001, _at(Vector3(x, 0.017, -0.012)), DARK)
	LowPoly.chamfer_box(metal, Vector3(0.024, 0.003, 0.006), 0.001, _at(Vector3(0, 0.0265, -0.012)), DARK)
	var glow := LowPoly.begin()
	LowPoly.chamfer_box(glow, Vector3(0.0035, 0.0035, 0.0015), 0.0006, _at(Vector3(0, 0.018, -0.006)), RETICLE)
	var glass := LowPoly.begin()
	LowPoly.box(glass, Vector3(0.018, 0.017, 0.001), _at(Vector3(0, 0.0175, -0.012)), GLASS)
	return _finish(metal, null, glow, glass)
