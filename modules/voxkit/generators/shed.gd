class_name VoxShed
extends VoxGenerator
## A plank shed on a concrete slab: vertical boards, gable roof in ribbed metal, a door gap
## at the front and framed windows around the sides. Hollow inside.

const PAINTS: Array[String] = ["Red barn", "Weathered", "Green", "White"]
const WALLS := [Color(0.55, 0.17, 0.12), Color(0.5, 0.42, 0.33), Color(0.25, 0.36, 0.25), Color(0.82, 0.8, 0.74)]
const TRIM := Color(0.88, 0.86, 0.8)
const ROOF := Color(0.32, 0.33, 0.35)
const CONCRETE := Color(0.58, 0.57, 0.54)
const GLASS := Color(0.2, 0.27, 0.32)
const DOOR_WIDTH := 1.0
const DOOR_HEIGHT := 2.0
const WINDOW := Vector2(0.8, 0.6)
const WINDOW_SILL := 1.1
const PLANK := 0.25
const OVERHANG := 0.3


func title() -> String:
	return "Shed"


func params() -> Array[Dictionary]:
	return [
		seed_param(),
		choice("paint", "Paint", PAINTS, 1),
		param("width", "Width (m)", 2.0, 9.0, 0.25, 4.5),
		param("depth", "Depth (m)", 2.0, 7.0, 0.25, 3.5),
		param("wall_height", "Wall height (m)", 2.2, 4.0, 0.1, 2.6),
		param("pitch", "Roof pitch", 0.0, 1.2, 0.05, 0.55),
		choice("door", "Door", ["No", "Yes"], 1),
		param("windows", "Windows", 0.0, 4.0, 1.0, 2.0),
		voxel_param(0.05, 0.25, 0.1),
	]


func build(values: Dictionary) -> VoxelModel:
	var p := with_defaults(values)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p["seed"])
	var seed := int(p["seed"])
	var w: float = p["width"]
	var d: float = p["depth"]
	var wh: float = p["wall_height"]
	var v: float = p["voxel"]
	var rise := d * 0.5 * float(p["pitch"])
	var wall: Color = WALLS[int(p["paint"])]
	var m := new_model()
	m.setup(Vector3(w + OVERHANG * 2.0 + v * 4.0, wh + rise + v * 4.0 + 0.3, d + OVERHANG * 2.0 + v * 4.0), v)
	var slab := 0.15
	m.fill_box(Vector3(-w / 2 - 0.1, 0, -d / 2 - 0.1), Vector3(w / 2 + 0.1, slab, d / 2 + 0.1), CONCRETE, 0.1, seed)
	# Walls as vertical boards, each its own shade, then the gable triangles at both ends.
	var x := -w / 2
	var board := 0
	while x < w / 2 - 0.001:
		var x1 := minf(x + PLANK, w / 2)
		m.fill_box(Vector3(x, slab, -d / 2), Vector3(x1, wh, d / 2), wall * rng.randf_range(0.86, 1.06), 0.07, seed + board)
		x = x1
		board += 1
	var steps := int(ceil(rise / v))
	for k in steps:
		var half := d / 2 * (1.0 - float(k + 1) / (steps + 1))
		m.fill_box(Vector3(-w / 2, wh + k * v, -half), Vector3(w / 2, wh + (k + 1) * v, half), wall, 0.07, seed + 40)
	var t := maxf(v * 2.0, 0.15)
	m.carve_box(Vector3(-w / 2 + t, slab, -d / 2 + t), Vector3(w / 2 - t, wh, d / 2 - t))
	# Corner trim.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			m.fill_box(Vector3(sx * w / 2 - v, slab, sz * d / 2 - v), Vector3(sx * w / 2 + v, wh, sz * d / 2 + v), TRIM, 0.04, seed)
	_roof(m, w, d, wh, rise, v, seed)
	if int(p["door"]) == 1:
		var top := minf(slab + DOOR_HEIGHT, wh - 0.2)
		m.carve_box(Vector3(-DOOR_WIDTH / 2, slab, -d / 2 - v), Vector3(DOOR_WIDTH / 2, top, -d / 2 + t + v))
		m.fill_box(Vector3(-DOOR_WIDTH / 2 - v, top, -d / 2 - v), Vector3(DOOR_WIDTH / 2 + v, top + v * 1.5, -d / 2 + v), TRIM, 0.04, seed)
	var spots := _window_spots(w, d, int(p["windows"]))
	for spot in spots:
		_window(m, spot, d, w, v, t, slab)
	return m


## Ribbed metal: rows down each slope, alternating shade, overhanging the walls.
func _roof(m: VoxelModel, w: float, d: float, wh: float, rise: float, v: float, seed: int) -> void:
	var half := d / 2 + OVERHANG
	var z := -half
	var row := 0
	var thick := maxf(v * 1.5, 0.12)
	while z < half:
		var slope := 1.0 - absf(z + v / 2) / (d / 2)
		var y := wh + rise * slope
		var shade := ROOF if row % 2 == 0 else ROOF.darkened(0.12)
		m.fill_box(Vector3(-w / 2 - OVERHANG, y, z), Vector3(w / 2 + OVERHANG, y + thick, z + v), shade, 0.05, seed + 70)
		z += v
		row += 1


## Where windows go, as [wall, along]: wall 0 back, 1 left, 2 right; along is a share of that
## wall's length.
func _window_spots(w: float, d: float, count: int) -> Array[Vector2]:
	var order: Array[Vector2] = [Vector2(1, 0.5), Vector2(2, 0.5), Vector2(0, 0.3), Vector2(0, 0.7)]
	var out: Array[Vector2] = []
	for i in mini(count, order.size()):
		out.append(order[i])
	return out


func _window(m: VoxelModel, spot: Vector2, d: float, w: float, v: float, t: float, slab: float) -> void:
	var wall := int(spot.x)
	var y0 := slab + WINDOW_SILL
	var y1 := y0 + WINDOW.y
	var half := WINDOW.x / 2
	var frame := v * 1.5
	if wall == 0:
		var cx := lerpf(-w / 2, w / 2, spot.y)
		var z := d / 2
		m.fill_box(Vector3(cx - half - frame, y0 - frame, z - v), Vector3(cx + half + frame, y1 + frame, z + v), TRIM, 0.04, 0)
		m.carve_box(Vector3(cx - half, y0, z - t - v), Vector3(cx + half, y1, z + v * 2.0))
		m.fill_box(Vector3(cx - half, y0, z - t * 0.5 - v * 0.5), Vector3(cx + half, y1, z - t * 0.5 + v * 0.5), GLASS, 0.0, 0)
	else:
		var cz := lerpf(-d / 2, d / 2, spot.y)
		var x := -w / 2 if wall == 1 else w / 2
		m.fill_box(Vector3(x - v, y0 - frame, cz - half - frame), Vector3(x + v, y1 + frame, cz + half + frame), TRIM, 0.04, 0)
		var inward := t if wall == 1 else -t
		m.carve_box(Vector3(minf(x - v * 2.0, x + inward), y0, cz - half), Vector3(maxf(x + v * 2.0, x + inward), y1, cz + half))
		m.fill_box(Vector3(x + inward * 0.5 - v * 0.5, y0, cz - half), Vector3(x + inward * 0.5 + v * 0.5, y1, cz + half), GLASS, 0.0, 0)
