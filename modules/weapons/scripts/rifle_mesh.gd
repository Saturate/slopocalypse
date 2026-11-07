class_name RifleMesh
extends RefCounted
## Geometry for the rifle, built from bevelled low-poly parts.
## Metres, rifle points down -Z, origin at the receiver. Built once at runtime and shared.

const GUNMETAL := Color(0.21, 0.22, 0.24)
const DARK := Color(0.08, 0.08, 0.09)
const POLYMER := Color(0.14, 0.14, 0.15)
const FURNITURE := Color(0.55, 0.47, 0.33)


static func _at(pos: Vector3, rot: Vector3 = Vector3.ZERO) -> Transform3D:
	return Transform3D(Basis.from_euler(rot), pos)


## Cylinders are built along Y; this lays one along the rifle's -Z axis.
static func _along_z(pos: Vector3) -> Transform3D:
	return Transform3D(Basis.from_euler(Vector3(PI / 2.0, 0.0, 0.0)), pos)


static func rifle() -> ArrayMesh:
	var metal := LowPoly.begin()
	LowPoly.chamfer_box(metal, Vector3(0.06, 0.07, 0.3), 0.008, _at(Vector3(0, 0.035, 0.0)), GUNMETAL)
	LowPoly.chamfer_box(metal, Vector3(0.068, 0.068, 0.27), 0.012, _at(Vector3(0, 0.035, -0.27)), GUNMETAL)
	LowPoly.chamfer_box(metal, Vector3(0.026, 0.012, 0.52), 0.003, _at(Vector3(0, 0.076, -0.13)), DARK)
	LowPoly.cylinder(metal, 0.011, 0.38, 10, _along_z(Vector3(0, 0.04, -0.4)), DARK)
	LowPoly.cylinder(metal, 0.018, 0.06, 8, _along_z(Vector3(0, 0.04, -0.6)), GUNMETAL)
	LowPoly.chamfer_box(metal, Vector3(0.008, 0.035, 0.012), 0.002, _at(Vector3(0, 0.1, -0.38)), DARK)
	LowPoly.chamfer_box(metal, Vector3(0.03, 0.02, 0.05), 0.004, _at(Vector3(0, 0.09, -0.02)), DARK)
	LowPoly.cylinder(metal, 0.024, 0.1, 10, _along_z(Vector3(0, 0.118, -0.02)), DARK)
	LowPoly.chamfer_box(metal, Vector3(0.022, 0.012, 0.035), 0.003, _at(Vector3(0, 0.072, 0.15)), DARK)
	LowPoly.chamfer_box(metal, Vector3(0.004, 0.026, 0.07), 0.001, _at(Vector3(0.031, 0.042, 0.0)), DARK)
	# Vent slots along both sides of the handguard.
	for i in 4:
		for side in [-1.0, 1.0]:
			LowPoly.chamfer_box(metal, Vector3(0.004, 0.012, 0.035), 0.001, _at(Vector3(side * 0.034, 0.035, -0.18 - i * 0.05)), DARK)
	var mesh := LowPoly.finish(metal, LowPoly.material(0.55, 0.3))

	var poly := LowPoly.begin()
	LowPoly.chamfer_box(poly, Vector3(0.056, 0.05, 0.22), 0.008, _at(Vector3(0, -0.015, 0.02)), POLYMER)
	# Curved magazine: three segments angling forward.
	LowPoly.chamfer_box(poly, Vector3(0.034, 0.075, 0.07), 0.006, _at(Vector3(0, -0.07, -0.04), Vector3(0.1, 0, 0)), FURNITURE)
	LowPoly.chamfer_box(poly, Vector3(0.034, 0.07, 0.068), 0.006, _at(Vector3(0, -0.135, -0.055), Vector3(0.28, 0, 0)), FURNITURE)
	LowPoly.chamfer_box(poly, Vector3(0.034, 0.06, 0.066), 0.006, _at(Vector3(0, -0.19, -0.08), Vector3(0.46, 0, 0)), FURNITURE)
	LowPoly.chamfer_box(poly, Vector3(0.036, 0.11, 0.046), 0.008, _at(Vector3(0, -0.075, 0.115), Vector3(-0.3, 0, 0)), FURNITURE)
	LowPoly.chamfer_box(poly, Vector3(0.008, 0.008, 0.06), 0.002, _at(Vector3(0, -0.052, 0.065)), POLYMER)
	LowPoly.chamfer_box(poly, Vector3(0.04, 0.04, 0.14), 0.006, _at(Vector3(0, 0.02, 0.2)), POLYMER)
	LowPoly.chamfer_box(poly, Vector3(0.046, 0.13, 0.045), 0.01, _at(Vector3(0, -0.005, 0.29)), FURNITURE)
	LowPoly.chamfer_box(poly, Vector3(0.04, 0.022, 0.11), 0.006, _at(Vector3(0, 0.05, 0.23)), FURNITURE)
	LowPoly.finish(poly, LowPoly.material(0.75), mesh)

	# The red dot glows so it reads at a glance.
	var dot := LowPoly.begin()
	LowPoly.chamfer_box(dot, Vector3(0.006, 0.006, 0.004), 0.001, _at(Vector3(0, 0.118, -0.068)), Color(1.0, 0.15, 0.1))
	var glow := LowPoly.material(0.3)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.1, 0.05)
	glow.emission_energy_multiplier = 4.0
	LowPoly.finish(dot, glow, mesh)
	return mesh
