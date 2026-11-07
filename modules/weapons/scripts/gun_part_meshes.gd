class_name GunPartMeshes
extends RefCounted
## Meshes for gun parts, each in its own space with the origin at the point it mounts on
## (the receiver's origin is the gun's). Metres; guns point down -Z. Original designs from
## bevelled low-poly pieces; built once at runtime and cached by mesh id.

const GUNMETAL := Color(0.21, 0.22, 0.24)
const DARK := Color(0.08, 0.08, 0.09)
const POLYMER := Color(0.14, 0.14, 0.15)
const FURNITURE := Color(0.55, 0.47, 0.33)
const RETICLE := Color(1.0, 0.15, 0.1)

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
		"handguard_std": built = _handguard(0.27, 4)
		"handguard_long": built = _handguard(0.36, 6)
		"stock_std": built = _stock_std()
		"stock_light": built = _stock_light()
		"grip_std": built = _grip_std()
		"mag_30": built = _magazine(3)
		"mag_45": built = _magazine(4)
		"muzzle_flash": built = _muzzle_flash()
		"muzzle_comp": built = _muzzle_comp()
		"muzzle_supp": built = _muzzle_supp()
		"optic_reddot": built = _optic_reddot()
		"optic_holo": built = _optic_holo()
	if built != null:
		_cache[id] = built
	return built


static func _at(pos: Vector3, rot: Vector3 = Vector3.ZERO) -> Transform3D:
	return Transform3D(Basis.from_euler(rot), pos)


## Cylinders are built along Y; this lays one along -Z.
static func _along_z(pos: Vector3) -> Transform3D:
	return Transform3D(Basis.from_euler(Vector3(PI / 2.0, 0.0, 0.0)), pos)


## A mesh from up to three surfaces: metal, polymer and a glowing reticle. Pass null for
## any a part does not have.
static func _finish(metal: SurfaceTool, poly: SurfaceTool = null, glow: SurfaceTool = null) -> ArrayMesh:
	var out := ArrayMesh.new()
	if metal != null:
		LowPoly.finish(metal, LowPoly.material(0.55, 0.3), out)
	if poly != null:
		LowPoly.finish(poly, LowPoly.material(0.75), out)
	if glow != null:
		var mat := LowPoly.material(0.3)
		mat.emission_enabled = true
		mat.emission = RETICLE
		mat.emission_energy_multiplier = 1.6
		LowPoly.finish(glow, mat, out)
	return out


static func _receiver_ar() -> ArrayMesh:
	var metal := LowPoly.begin()
	LowPoly.chamfer_box(metal, Vector3(0.06, 0.07, 0.3), 0.008, _at(Vector3(0, 0.035, 0.0)), GUNMETAL)
	# The receiver's stretch of top rail; each handguard carries the rest, so the rail is
	# always as long as the gun.
	LowPoly.chamfer_box(metal, Vector3(0.026, 0.012, 0.29), 0.003, _at(Vector3(0, 0.076, -0.005)), DARK)
	LowPoly.chamfer_box(metal, Vector3(0.022, 0.012, 0.035), 0.003, _at(Vector3(0, 0.072, 0.15)), DARK)
	LowPoly.chamfer_box(metal, Vector3(0.004, 0.026, 0.07), 0.001, _at(Vector3(0.031, 0.042, 0.0)), DARK)
	var poly := LowPoly.begin()
	LowPoly.chamfer_box(poly, Vector3(0.056, 0.05, 0.22), 0.008, _at(Vector3(0, -0.015, 0.02)), POLYMER)
	# Trigger guard: a closed loop under the receiver, with the trigger inside it.
	LowPoly.chamfer_box(poly, Vector3(0.012, 0.007, 0.07), 0.002, _at(Vector3(0, -0.064, 0.07)), POLYMER)
	LowPoly.chamfer_box(poly, Vector3(0.012, 0.028, 0.007), 0.002, _at(Vector3(0, -0.053, 0.036)), POLYMER)
	LowPoly.chamfer_box(poly, Vector3(0.006, 0.022, 0.006), 0.001, _at(Vector3(0, -0.05, 0.06), Vector3(-0.25, 0, 0)), DARK)
	return _finish(metal, poly)


static func _barrel(length: float) -> ArrayMesh:
	var metal := LowPoly.begin()
	LowPoly.cylinder(metal, 0.011, length, 10, _along_z(Vector3(0, 0, -length / 2.0)), DARK)
	LowPoly.chamfer_box(metal, Vector3(0.026, 0.03, 0.03), 0.004, _at(Vector3(0, 0.006, -length * 0.55)), GUNMETAL)
	return _finish(metal)


static func _handguard(length: float, vents: int) -> ArrayMesh:
	var metal := LowPoly.begin()
	LowPoly.chamfer_box(metal, Vector3(0.068, 0.068, length), 0.012, _at(Vector3(0, 0, -length / 2.0)), GUNMETAL)
	LowPoly.chamfer_box(metal, Vector3(0.026, 0.012, length), 0.003, _at(Vector3(0, 0.041, -length / 2.0)), DARK)
	LowPoly.chamfer_box(metal, Vector3(0.008, 0.035, 0.012), 0.002, _at(Vector3(0, 0.065, -length + 0.025)), DARK)
	for i in vents:
		for side in [-1.0, 1.0]:
			LowPoly.chamfer_box(metal, Vector3(0.004, 0.012, 0.035), 0.001, _at(Vector3(side * 0.034, 0.0, -0.045 - i * 0.05)), DARK)
	return _finish(metal)


static func _stock_std() -> ArrayMesh:
	var poly := LowPoly.begin()
	LowPoly.chamfer_box(poly, Vector3(0.04, 0.04, 0.14), 0.006, _at(Vector3(0, 0, 0.07)), POLYMER)
	LowPoly.chamfer_box(poly, Vector3(0.046, 0.13, 0.045), 0.01, _at(Vector3(0, -0.025, 0.16)), FURNITURE)
	LowPoly.chamfer_box(poly, Vector3(0.04, 0.022, 0.11), 0.006, _at(Vector3(0, 0.03, 0.1)), FURNITURE)
	return _finish(null, poly)


static func _stock_light() -> ArrayMesh:
	var metal := LowPoly.begin()
	LowPoly.cylinder(metal, 0.012, 0.15, 8, _along_z(Vector3(0, 0, 0.075)), GUNMETAL)
	LowPoly.cylinder(metal, 0.007, 0.16, 6, _along_z(Vector3(0, -0.05, 0.08)), GUNMETAL)
	var poly := LowPoly.begin()
	LowPoly.chamfer_box(poly, Vector3(0.04, 0.12, 0.02), 0.006, _at(Vector3(0, -0.03, 0.165)), POLYMER)
	return _finish(metal, poly)


static func _grip_std() -> ArrayMesh:
	var poly := LowPoly.begin()
	LowPoly.chamfer_box(poly, Vector3(0.036, 0.11, 0.046), 0.008, _at(Vector3(0, -0.035, 0.015), Vector3(-0.3, 0, 0)), FURNITURE)
	return _finish(null, poly)


## A curved box magazine: segments angling further forward the lower they sit.
static func _magazine(segments: int) -> ArrayMesh:
	var poly := LowPoly.begin()
	var pos := Vector3(0, -0.035, 0)
	for i in segments:
		var tilt := 0.1 + 0.18 * i
		LowPoly.chamfer_box(poly, Vector3(0.034, 0.072, 0.07 - i * 0.002), 0.006, _at(pos, Vector3(tilt, 0, 0)), FURNITURE)
		pos += Vector3(0, -0.062, -0.012 - 0.012 * i)
	return _finish(null, poly)


static func _muzzle_flash() -> ArrayMesh:
	var metal := LowPoly.begin()
	LowPoly.cylinder(metal, 0.018, 0.06, 8, _along_z(Vector3(0, 0, -0.03)), GUNMETAL)
	# Slots between prongs near the tip.
	for i in 4:
		var a := TAU * i / 4.0
		LowPoly.chamfer_box(metal, Vector3(0.006, 0.006, 0.03), 0.001, Transform3D(Basis(Vector3.BACK, a), Vector3(cos(a) * 0.0165, sin(a) * 0.0165, -0.042)), DARK)
	return _finish(metal)


static func _muzzle_comp() -> ArrayMesh:
	var metal := LowPoly.begin()
	LowPoly.chamfer_box(metal, Vector3(0.032, 0.032, 0.065), 0.006, _at(Vector3(0, 0, -0.0325)), GUNMETAL)
	# Ports on top vent gas upward, which is what holds the muzzle down.
	for i in 3:
		LowPoly.chamfer_box(metal, Vector3(0.02, 0.006, 0.008), 0.001, _at(Vector3(0, 0.016, -0.015 - i * 0.017)), DARK)
	return _finish(metal)


static func _muzzle_supp() -> ArrayMesh:
	var metal := LowPoly.begin()
	LowPoly.cylinder(metal, 0.022, 0.17, 12, _along_z(Vector3(0, 0, -0.085)), DARK)
	for z in [-0.02, -0.15]:
		LowPoly.cylinder(metal, 0.0235, 0.012, 12, _along_z(Vector3(0, 0, z)), GUNMETAL)
	return _finish(metal)


## Red dot: an open tube housing to look through, the dot near its front lens.
static func _optic_reddot() -> ArrayMesh:
	var metal := LowPoly.begin()
	LowPoly.chamfer_box(metal, Vector3(0.03, 0.02, 0.05), 0.004, _at(Vector3(0, 0.008, 0)), DARK)
	LowPoly.tube(metal, 0.023, 0.0205, 0.07, 20, _along_z(Vector3(0, 0.036, 0)), DARK)
	var glow := LowPoly.begin()
	LowPoly.chamfer_box(glow, Vector3(0.004, 0.004, 0.002), 0.0008, _at(Vector3(0, 0.036, -0.0245)), RETICLE)
	return _finish(metal, null, glow)


## Holo sight: a square window on a block base, a ring-and-dot reticle in the window.
static func _optic_holo() -> ArrayMesh:
	var metal := LowPoly.begin()
	LowPoly.chamfer_box(metal, Vector3(0.036, 0.014, 0.075), 0.004, _at(Vector3(0, 0.005, 0.005)), DARK)
	# Side walls and a hood around the window give it its boxy holo profile from the side.
	for x in [-0.024, 0.024]:
		LowPoly.chamfer_box(metal, Vector3(0.006, 0.048, 0.055), 0.002, _at(Vector3(x, 0.034, -0.005)), DARK)
	LowPoly.chamfer_box(metal, Vector3(0.054, 0.006, 0.055), 0.002, _at(Vector3(0, 0.06, -0.005)), DARK)
	LowPoly.chamfer_box(metal, Vector3(0.03, 0.012, 0.02), 0.003, _at(Vector3(0.0, 0.018, 0.03)), DARK)
	var glow := LowPoly.begin()
	LowPoly.tube(glow, 0.009, 0.0075, 0.001, 16, _along_z(Vector3(0, 0.034, -0.02)), RETICLE)
	LowPoly.chamfer_box(glow, Vector3(0.002, 0.002, 0.001), 0.0004, _at(Vector3(0, 0.034, -0.02)), RETICLE)
	return _finish(metal, null, glow)
