class_name VoxRock
extends VoxGenerator
## A boulder: a lumpy ellipsoid sunk into the ground, with moss on top.

const GREY := Color(0.4, 0.4, 0.39)
const SANDSTONE := Color(0.58, 0.48, 0.35)
const MOSS := Color(0.3, 0.42, 0.18)


func title() -> String:
	return "Rock"


func params() -> Array[Dictionary]:
	return [
		seed_param(),
		param("width", "Width (m)", 0.3, 5.0, 0.1, 1.6),
		param("height", "Height", 0.2, 1.2, 0.05, 0.6),
		param("bumps", "Bumpiness", 0.0, 0.5, 0.02, 0.24),
		param("moss", "Moss", 0.0, 1.0, 0.05, 0.35),
		param("tone", "Grey to sandstone", 0.0, 1.0, 0.05, 0.0),
		voxel_param(0.03, 0.25, 0.08),
	]


func build(values: Dictionary) -> VoxelModel:
	var p := with_defaults(values)
	var seed := int(p["seed"])
	var w: float = p["width"]
	var h: float = w * float(p["height"])
	var bumps: float = p["bumps"]
	var m := VoxelModel.new()
	m.setup(Vector3(w * (1.3 + bumps * 2.0), h * (1.2 + bumps * 2.0) + 0.2, w * (1.3 + bumps * 2.0)), p["voxel"])
	var colour := GREY.lerp(SANDSTONE, float(p["tone"]))
	# Centred low so the ground cuts the bottom off flat.
	var centre := Vector3(0, h * 0.35, 0)
	m.fill_blob(centre, Vector3(w * 0.5, h * 0.65, w * 0.44), bumps, 2.4 / w, colour, 0.14, seed)
	# A second, smaller lump off to one side so it isn't a dome.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var a := rng.randf() * TAU
	m.fill_blob(centre + Vector3(cos(a) * w * 0.3, h * 0.1, sin(a) * w * 0.3), Vector3(w * 0.32, h * 0.5, w * 0.3), bumps, 3.0 / w, colour.darkened(0.06), 0.14, seed + 7)
	# Darker streaks low down, moss on the top.
	m.paint_box(Vector3(-w, 0, -w), Vector3(w, h * 0.12, w), colour.darkened(0.25), 0.12, seed + 1)
	var moss: float = p["moss"]
	if moss > 0.0:
		m.paint_ellipsoid(centre + Vector3.UP * h * 0.75, Vector3(w * (0.25 + moss * 0.5), h * (0.15 + moss * 0.35), w * (0.25 + moss * 0.5)), MOSS, 0.22, seed + 2)
	return m
