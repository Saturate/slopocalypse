class_name VoxPineTree
extends VoxGenerator
## A conifer: a tapering trunk and stacked, shrinking layers of needles, darker underneath.

const BARK := Color(0.33, 0.22, 0.14)
const NEEDLES := Color(0.16, 0.3, 0.17)
const NEEDLES_LIT := Color(0.27, 0.42, 0.22)
const SNOW := Color(0.92, 0.94, 0.97)


func title() -> String:
	return "Pine tree"


func params() -> Array[Dictionary]:
	return [
		seed_param(),
		param("height", "Height (m)", 3.0, 18.0, 0.5, 10.0),
		param("trunk", "Trunk width (m)", 0.15, 0.9, 0.05, 0.4),
		param("layers", "Layers", 3.0, 14.0, 1.0, 8.0),
		param("width", "Width", 0.15, 0.55, 0.01, 0.3),
		param("droop", "Droop", 0.0, 1.0, 0.05, 0.5),
		param("snow", "Snow", 0.0, 1.0, 0.05, 0.0),
		voxel_param(0.04, 0.3, 0.1),
	]


func build(values: Dictionary) -> VoxelModel:
	var p := with_defaults(values)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p["seed"])
	var h: float = p["height"]
	var r0 := float(p["width"]) * h
	var seed := int(p["seed"])
	var m := new_model()
	m.setup(Vector3(r0 * 2.6 + 1.0, h + 1.0, r0 * 2.6 + 1.0), p["voxel"])
	var trunk: float = p["trunk"]
	m.fill_capsule(Vector3(0, -0.3, 0), Vector3(0, h * 0.97, 0), trunk * 0.5, trunk * 0.12, BARK, 0.18, seed)
	var layers := int(p["layers"])
	var droop: float = p["droop"]
	var lean := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 0.04 * h
	for i in layers:
		var t := float(i) / maxf(layers - 1.0, 1.0)
		var y := h * (0.2 + 0.74 * t)
		var r := lerpf(r0, r0 * 0.12, pow(t, 0.9)) * rng.randf_range(0.88, 1.08)
		var thick := maxf(r * 0.42, float(p["voxel"]) * 3.0)
		var c := Vector3(lean.x * t, y, lean.y * t)
		# The layer, its hanging skirt, then light painted on the upper side.
		m.fill_blob(c, Vector3(r, thick, r), 0.28, 1.4, NEEDLES, 0.2, seed + i)
		if droop > 0.0:
			m.fill_blob(c + Vector3.DOWN * thick * 0.9, Vector3(r * (0.75 + droop * 0.35), thick * (0.25 + droop * 0.35), r * (0.75 + droop * 0.35)), 0.3, 1.8, NEEDLES, 0.2, seed + 100 + i)
		m.paint_ellipsoid(c + Vector3.UP * thick * 0.55, Vector3(r * 0.9, thick * 0.7, r * 0.9), NEEDLES_LIT, 0.2, seed + i)
		if float(p["snow"]) > 0.0:
			m.paint_ellipsoid(c + Vector3.UP * thick * (1.3 - float(p["snow"]) * 0.5), Vector3(r, thick * 0.6, r), SNOW, 0.05, seed + i)
	m.fill_capsule(Vector3(lean.x, h * 0.9, lean.y), Vector3(lean.x, h, lean.y), r0 * 0.1, 0.02, NEEDLES_LIT, 0.15, seed)
	return m
