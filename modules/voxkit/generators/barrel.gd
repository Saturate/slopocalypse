class_name VoxBarrel
extends VoxGenerator
## A steel drum with raised rings, a recessed lid with a bung, dents and rust.

const PAINTS: Array[String] = ["Blue", "Red", "Olive", "Rusty"]
const COLOURS := [Color(0.24, 0.33, 0.45), Color(0.55, 0.2, 0.15), Color(0.36, 0.4, 0.24), Color(0.45, 0.28, 0.17)]
const RUST := Color(0.5, 0.27, 0.12)


func title() -> String:
	return "Barrel"


func params() -> Array[Dictionary]:
	return [
		seed_param(),
		choice("paint", "Paint", PAINTS, 0),
		param("radius", "Radius (m)", 0.2, 0.6, 0.01, 0.3),
		param("height", "Height (m)", 0.5, 1.4, 0.05, 0.9),
		param("rings", "Rings", 0.0, 4.0, 1.0, 2.0),
		param("dents", "Dents", 0.0, 8.0, 1.0, 2.0),
		param("rust", "Rust", 0.0, 1.0, 0.05, 0.25),
		voxel_param(0.015, 0.08, 0.03),
	]


func build(values: Dictionary) -> VoxelModel:
	var p := with_defaults(values)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p["seed"])
	var seed := int(p["seed"])
	var r: float = p["radius"]
	var h: float = p["height"]
	var v: float = p["voxel"]
	var paint: Color = COLOURS[int(p["paint"])]
	var m := new_model()
	m.setup(Vector3(r * 2.0 + v * 6.0, h + v * 3.0, r * 2.0 + v * 6.0), v)
	m.fill_cylinder(Vector3.ZERO, r, h, paint, 0.08, seed)
	var rings := int(p["rings"])
	for i in rings:
		var y := h * float(i + 1) / (rings + 1)
		m.fill_cylinder(Vector3(0, y - v, 0), r + v, v * 2.0, paint.darkened(0.15), 0.06, seed + 1)
	# Rolled rims top and bottom, a recessed lid, the bung.
	m.fill_cylinder(Vector3.ZERO, r + v * 0.6, v * 1.5, paint.darkened(0.2), 0.06, seed + 2)
	m.fill_cylinder(Vector3(0, h - v * 1.5, 0), r + v * 0.6, v * 1.5, paint.darkened(0.2), 0.06, seed + 2)
	m.carve_box(Vector3(-r * 0.85, h - v, -r * 0.85), Vector3(r * 0.85, h + v, r * 0.85))
	m.fill_cylinder(Vector3(-r * 0.2, h - v, 0), r * 0.12, v * 1.6, paint.darkened(0.3), 0.0, seed)
	for i in int(p["dents"]):
		var a := rng.randf() * TAU
		m.carve_ellipsoid(Vector3(cos(a) * r * 1.05, rng.randf_range(0.15, 0.85) * h, sin(a) * r * 1.05), Vector3.ONE * r * rng.randf_range(0.18, 0.3))
	var rust: float = p["rust"]
	for i in int(rust * 18.0):
		var a := rng.randf() * TAU
		m.paint_ellipsoid(Vector3(cos(a) * r, rng.randf_range(0.0, 1.0) * h * (1.0 - rust * 0.5), sin(a) * r), Vector3.ONE * r * rng.randf_range(0.15, 0.4), RUST, 0.25, seed + i)
	return m
