class_name VoxSupplyCrate
extends VoxGenerator
## A plank crate with a darker frame and grooves between boards; military style is green
## with a yellow band.

const STYLES: Array[String] = ["Wood", "Military"]
const BOARD := [Color(0.62, 0.47, 0.3), Color(0.31, 0.37, 0.24)]
const FRAME := [Color(0.42, 0.3, 0.19), Color(0.22, 0.27, 0.17)]
const BAND := Color(0.85, 0.7, 0.2)


func title() -> String:
	return "Supply crate"


func params() -> Array[Dictionary]:
	return [
		seed_param(),
		choice("style", "Style", STYLES, 0),
		param("width", "Width (m)", 0.4, 1.8, 0.05, 1.0),
		param("height", "Height (m)", 0.3, 1.4, 0.05, 0.7),
		param("depth", "Depth (m)", 0.3, 1.4, 0.05, 0.7),
		param("planks", "Planks", 2.0, 8.0, 1.0, 4.0),
		param("wear", "Wear", 0.0, 1.0, 0.05, 0.3),
		voxel_param(0.015, 0.1, 0.035),
	]


func build(values: Dictionary) -> VoxelModel:
	var p := with_defaults(values)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p["seed"])
	var seed := int(p["seed"])
	var style := int(p["style"])
	var w: float = p["width"]
	var h: float = p["height"]
	var d: float = p["depth"]
	var v: float = p["voxel"]
	var m := new_model()
	m.setup(Vector3(w + v * 4.0, h + v * 2.0, d + v * 4.0), v)
	var board: Color = BOARD[style]
	var frame: Color = FRAME[style]
	m.fill_box(Vector3(-w / 2, 0, -d / 2), Vector3(w / 2, h, d / 2), board, 0.1, seed)
	# Each plank its own shade, a groove carved between them.
	var planks := int(p["planks"])
	for i in planks:
		var y0 := h * i / planks
		var y1 := h * (i + 1) / planks
		m.paint_box(Vector3(-w, y0, -d), Vector3(w, y1, d), board * rng.randf_range(0.88, 1.06), 0.1, seed + i)
		if i > 0:
			_groove(m, w, d, y0, v)
	var t := maxf(v * 2.0, minf(w, d) * 0.08)
	# Frame: corner posts and rims stand a voxel proud of the boards, braces cross the
	# front and back, so it reads as a crate and not a pile of planks.
	var out := v
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var x0 := sx * w / 2
			var z0 := sz * d / 2
			# From t inside the corner to one voxel outside it, whichever side that is.
			var xa := x0 - sx * t
			var xb := x0 + sx * out
			var za := z0 - sz * t
			var zb := z0 + sz * out
			m.fill_box(Vector3(minf(xa, xb), 0, minf(za, zb)), Vector3(maxf(xa, xb), h, maxf(za, zb)), frame, 0.08, seed + 20)
	for y in [0.0, h - t]:
		m.fill_box(Vector3(-w / 2 - out, y, -d / 2 - out), Vector3(w / 2 + out, y + t, d / 2 + out), frame, 0.08, seed + 21)
	for sz: float in [-1.0, 1.0]:
		var face := sz * (d / 2 + out * 0.5)
		m.fill_capsule(Vector3(-w / 2 + t, t, face), Vector3(w / 2 - t, h - t, face), t * 0.45, t * 0.45, frame, 0.08, seed + 23)
	m.fill_box(Vector3(-w / 2 + t, h - v * 0.5, -d / 2 + t), Vector3(w / 2 - t, h, d / 2 - t), board, 0.1, seed + 22)
	if style == 1:
		m.paint_box(Vector3(-w, h * 0.45, -d), Vector3(w, h * 0.55, d), BAND, 0.05, seed)
	var wear: float = p["wear"]
	for i in int(wear * 14.0):
		var at := Vector3(rng.randf_range(-w, w) / 2, rng.randf_range(0, h), rng.randf_range(-d, d) / 2)
		m.paint_ellipsoid(at, Vector3.ONE * rng.randf_range(0.04, 0.12) * maxf(w, 0.5), board.darkened(0.35), 0.15, seed + i)
	return m


func _groove(m: VoxelModel, w: float, d: float, y: float, v: float) -> void:
	var lo := y - v * 0.5
	var hi := y + v * 0.5
	m.carve_box(Vector3(-w, lo, -d / 2 - v), Vector3(w, hi, -d / 2 + v * 0.6))
	m.carve_box(Vector3(-w, lo, d / 2 - v * 0.6), Vector3(w, hi, d / 2 + v))
	m.carve_box(Vector3(-w / 2 - v, lo, -d), Vector3(-w / 2 + v * 0.6, hi, d))
	m.carve_box(Vector3(w / 2 - v * 0.6, lo, -d), Vector3(w / 2 + v, hi, d))
