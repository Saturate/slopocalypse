class_name VoxBoatShed
extends VoxGenerator
## A harbour boat shed: a narrow wooden shed of vertical boards on a low plank floor, its
## gable end to the water (+z) with a pair of wide doors (open, or shut with a white cross
## brace), a steep roof whose ridge runs from the land end to the water end, white
## bargeboards and corner boards, and a small window in each long side. Hollow inside, room
## for a boat. Centred on the origin, standing on y 0. `collision` sizes its boxes from the
## same walls and roof.

const PAINTS: Array[String] = ["Tarred black", "Falu red", "White", "Blue-grey", "Ochre"]
const WALLS := [Color(0.14, 0.13, 0.12), Color(0.52, 0.15, 0.11), Color(0.86, 0.85, 0.8), Color(0.42, 0.5, 0.55), Color(0.78, 0.58, 0.24)]
## Trim on the pale paints is dark, on the rest white.
const TRIMS := [Color(0.9, 0.89, 0.84), Color(0.9, 0.89, 0.84), Color(0.25, 0.3, 0.33), Color(0.9, 0.89, 0.84), Color(0.9, 0.89, 0.84)]
const DOORS: Array[String] = ["Open", "Shut"]
const ROOF := Color(0.2, 0.2, 0.21)
const FLOOR := Color(0.48, 0.39, 0.28)
const GLASS := Color(0.2, 0.27, 0.32)
const PLANK := 0.22
const WALL_THICK := 0.12
const FLOOR_HEIGHT := 0.2
const OVERHANG := 0.25
const ROOF_THICK := 0.12
const WINDOW := Vector2(0.6, 0.5)
const WINDOW_SILL := 1.2
## The doorway leaves this much wall either side, metres.
const DOOR_JAMB := 0.3
## Over the doorway, under the eaves.
const DOOR_HEAD := 0.2
## How many boxes the roof's collision takes per slope.
const ROOF_STEPS := 4


func title() -> String:
	return "Boat shed"


func params() -> Array[Dictionary]:
	return [
		seed_param(),
		choice("paint", "Paint", PAINTS, 1),
		param("width", "Width (m)", 2.6, 6.0, 0.1, 3.2),
		param("depth", "Depth (m)", 4.0, 10.0, 0.25, 7.0),
		param("wall_height", "Wall height (m)", 2.2, 3.6, 0.1, 2.5),
		param("pitch", "Roof pitch", 0.4, 1.4, 0.05, 0.9),
		choice("doors", "Doors", DOORS, 0),
		voxel_param(0.05, 0.15, 0.08),
	]


## How thick the walls are drawn and collide: at least a voxel and a half, so a coarse
## voxel still leaves a whole cell of wall.
static func wall_thick(v: float) -> float:
	return maxf(WALL_THICK, v * 1.5)


## Ridge height above the wall tops, metres.
static func rise(values: Dictionary) -> float:
	var p := VoxBoatShed.new().with_defaults(values)
	return float(p["width"]) * 0.5 * float(p["pitch"])


## The doorway in the water end, as x from -half to half and y from the floor up.
static func doorway(values: Dictionary) -> Vector2:
	var p := VoxBoatShed.new().with_defaults(values)
	return Vector2(float(p["width"]) - DOOR_JAMB * 2.0, float(p["wall_height"]) - DOOR_HEAD - FLOOR_HEIGHT)


## Collision boxes (model space): the floor, the side and land-end walls, the water end
## either side of and over the doorway (closed across it when shut), and each roof slope as a
## few steps.
static func collision(values: Dictionary) -> Array[AABB]:
	var p := VoxBoatShed.new().with_defaults(values)
	var w: float = p["width"]
	var d: float = p["depth"]
	var wh: float = p["wall_height"]
	var t := wall_thick(float(p["voxel"]))
	var out: Array[AABB] = [AABB(Vector3(-w / 2.0, 0.0, -d / 2.0), Vector3(w, FLOOR_HEIGHT, d))]
	out.append(AABB(Vector3(-w / 2.0, FLOOR_HEIGHT, -d / 2.0), Vector3(t, wh - FLOOR_HEIGHT, d)))
	out.append(AABB(Vector3(w / 2.0 - t, FLOOR_HEIGHT, -d / 2.0), Vector3(t, wh - FLOOR_HEIGHT, d)))
	out.append(AABB(Vector3(-w / 2.0, FLOOR_HEIGHT, -d / 2.0), Vector3(w, wh - FLOOR_HEIGHT, t)))
	var door := doorway(p)
	var front := d / 2.0 - t
	if int(p["doors"]) == 1:
		out.append(AABB(Vector3(-w / 2.0, FLOOR_HEIGHT, front), Vector3(w, wh - FLOOR_HEIGHT, t + float(p["voxel"]))))
	else:
		out.append(AABB(Vector3(-w / 2.0, FLOOR_HEIGHT, front), Vector3(DOOR_JAMB, wh - FLOOR_HEIGHT, t)))
		out.append(AABB(Vector3(w / 2.0 - DOOR_JAMB, FLOOR_HEIGHT, front), Vector3(DOOR_JAMB, wh - FLOOR_HEIGHT, t)))
		out.append(AABB(Vector3(-door.x / 2.0, FLOOR_HEIGHT + door.y, front), Vector3(door.x, wh - FLOOR_HEIGHT - door.y, t)))
	var r := rise(p)
	# The gables at both ends, stepped.
	for k in ROOF_STEPS:
		var gx := w / 2.0 * (1.0 - float(k) / ROOF_STEPS)
		var y0 := wh + r * float(k) / ROOF_STEPS
		for z: float in [-d / 2.0, d / 2.0 - t]:
			out.append(AABB(Vector3(-gx, y0, z), Vector3(gx * 2.0, r / ROOF_STEPS, t)))
	var half := w / 2.0 + OVERHANG
	for k in ROOF_STEPS:
		var x0 := half * float(k) / ROOF_STEPS
		var x1 := half * float(k + 1) / ROOF_STEPS
		# Each step at the roof's height over its outer edge, so nothing pokes up through it.
		var y := wh + r * (1.0 - x1 / (w / 2.0))
		for side: float in [-1.0, 1.0]:
			var a := side * x0
			var b := side * x1
			out.append(AABB(Vector3(minf(a, b), y, -d / 2.0 - OVERHANG), Vector3(x1 - x0, ROOF_THICK + r / ROOF_STEPS, d + OVERHANG * 2.0)))
	return out


func build(values: Dictionary) -> VoxelModel:
	var p := with_defaults(values)
	var seed := int(p["seed"])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var w: float = p["width"]
	var d: float = p["depth"]
	var wh: float = p["wall_height"]
	var v: float = p["voxel"]
	var paint := clampi(int(p["paint"]), 0, WALLS.size() - 1)
	var wall: Color = WALLS[paint]
	var trim: Color = TRIMS[paint]
	var r := rise(p)
	var shut := int(p["doors"]) == 1
	var m := new_model()
	m.setup(Vector3(w + OVERHANG * 2.0 + v * 4.0, wh + r + ROOF_THICK * 2.0 + v * 4.0, d + OVERHANG * 2.0 + v * 4.0), v)
	var wood := VoxMaterials.index_of("wood")
	m.set_material(wood)
	m.fill_box(Vector3(-w / 2.0, 0.0, -d / 2.0), Vector3(w / 2.0, FLOOR_HEIGHT, d / 2.0), FLOOR, 0.08, seed)
	# Walls in vertical boards along both long sides and both ends, each its own shade.
	var x := -w / 2.0
	var board := 0
	while x < w / 2.0 - 0.001:
		var x1 := minf(x + PLANK, w / 2.0)
		var shade := wall * rng.randf_range(0.88, 1.08)
		m.fill_box(Vector3(x, FLOOR_HEIGHT, -d / 2.0), Vector3(x1, wh, d / 2.0), shade, 0.06, seed + board)
		# The gable over each end, board by board up to the roof line.
		var mid := (x + x1) / 2.0
		var top := wh + r * (1.0 - absf(mid) / (w / 2.0))
		m.fill_box(Vector3(x, wh, -d / 2.0), Vector3(x1, top, -d / 2.0 + wall_thick(v)), shade, 0.06, seed + board)
		m.fill_box(Vector3(x, wh, d / 2.0 - wall_thick(v)), Vector3(x1, top, d / 2.0), shade, 0.06, seed + board)
		x = x1
		board += 1
	var t := wall_thick(v)
	m.carve_box(Vector3(-w / 2.0 + t, FLOOR_HEIGHT, -d / 2.0 + t), Vector3(w / 2.0 - t, wh + 0.01, d / 2.0 - t))
	# Corner boards.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			m.fill_box(Vector3(sx * w / 2.0 - v, FLOOR_HEIGHT, sz * d / 2.0 - v), Vector3(sx * w / 2.0 + v, wh, sz * d / 2.0 + v), trim, 0.03, seed)
	_doors(m, p, wall, trim, shut, v, seed)
	_windows(m, w, d, v, trim, wood)
	m.set_material(VoxMaterials.index_of("sheet_metal"))
	_roof(m, w, d, wh, r, v, seed)
	m.set_material(wood)
	# Bargeboards along both gable edges, just proud of the roof.
	var steps := int(ceil((w / 2.0 + OVERHANG) / v))
	for i in steps:
		var bx := float(i) * v
		var y := wh + r * (1.0 - bx / (w / 2.0)) + ROOF_THICK * 0.5
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var x0 := sx * bx
				m.fill_box(Vector3(minf(x0, x0 + sx * v), y - v * 1.5, sz * (d / 2.0 + OVERHANG) - v), Vector3(maxf(x0, x0 + sx * v), y + v, sz * (d / 2.0 + OVERHANG) + v), trim, 0.03, seed + 90)
	return m


## The water end's doorway: carved through, with its frame; shut, two leaves with a white
## (or dark) cross brace on each.
func _doors(m: VoxelModel, p: Dictionary, wall: Color, trim: Color, shut: bool, v: float, seed: int) -> void:
	var d: float = p["depth"]
	var door := doorway(p)
	var z := d / 2.0
	var y0 := FLOOR_HEIGHT
	var y1 := FLOOR_HEIGHT + door.y
	m.carve_box(Vector3(-door.x / 2.0, y0, z - WALL_THICK - v * 2.0), Vector3(door.x / 2.0, y1, z + v))
	var f := maxf(v * 1.5, 0.1)
	m.fill_box(Vector3(-door.x / 2.0 - f, y0, z - v), Vector3(-door.x / 2.0, y1 + f, z + v), trim, 0.03, seed)
	m.fill_box(Vector3(door.x / 2.0, y0, z - v), Vector3(door.x / 2.0 + f, y1 + f, z + v), trim, 0.03, seed)
	m.fill_box(Vector3(-door.x / 2.0 - f, y1, z - v), Vector3(door.x / 2.0 + f, y1 + f, z + v), trim, 0.03, seed)
	if not shut:
		return
	for side: float in [-1.0, 1.0]:
		var xa := side * 0.01
		var xb := side * door.x / 2.0
		var lo := minf(xa, xb)
		var hi := maxf(xa, xb)
		m.fill_box(Vector3(lo, y0, z - wall_thick(v)), Vector3(hi, y1, z), wall.darkened(0.08), 0.05, seed + 60)
		# The braces stand one voxel proud of the leaves, inside the shut front's collision.
		var face := z + v * 0.5
		var br := maxf(v * 0.6, 0.04)
		m.fill_capsule(Vector3(lo + f, y0 + f, face), Vector3(hi - f, y1 - f, face), br, br, trim, 0.03, seed)
		m.fill_capsule(Vector3(lo + f, y1 - f, face), Vector3(hi - f, y0 + f, face), br, br, trim, 0.03, seed)
		m.fill_box(Vector3(lo, y0, face - v * 0.5), Vector3(hi, y0 + f, face + v * 0.5), trim, 0.03, seed)
		m.fill_box(Vector3(lo, y1 - f, face - v * 0.5), Vector3(hi, y1, face + v * 0.5), trim, 0.03, seed)


## One small window in the middle of each long side.
func _windows(m: VoxelModel, w: float, d: float, v: float, trim: Color, wood: int) -> void:
	var glass := VoxMaterials.index_of("window_glass")
	var y0 := WINDOW_SILL
	var y1 := y0 + WINDOW.y
	var half := WINDOW.x / 2.0
	var frame := maxf(v * 1.5, 0.08)
	for side: float in [-1.0, 1.0]:
		var x := side * w / 2.0
		m.set_material(wood)
		m.fill_box(Vector3(x - v, y0 - frame, -half - frame), Vector3(x + v, y1 + frame, half + frame), trim, 0.03, 0)
		m.carve_box(Vector3(x - WALL_THICK - v * 2.0, y0, -half), Vector3(x + WALL_THICK + v * 2.0, y1, half))
		m.set_material(glass)
		m.fill_box(Vector3(x - v * 0.5, y0, -half), Vector3(x + v * 0.5, y1, half), GLASS, 0.0, 0)
	m.set_material(wood)


## Ribbed sheets down both slopes, running from the ridge to the eaves.
func _roof(m: VoxelModel, w: float, d: float, wh: float, r: float, v: float, seed: int) -> void:
	var half := w / 2.0 + OVERHANG
	var x := 0.0
	var row := 0
	while x < half:
		var y := wh + r * (1.0 - (x + v / 2.0) / (w / 2.0))
		var shade := ROOF if row % 3 != 0 else ROOF.lightened(0.08)
		for side: float in [-1.0, 1.0]:
			var a := side * x
			var b := side * (x + v)
			m.fill_box(Vector3(minf(a, b), y, -d / 2.0 - OVERHANG), Vector3(maxf(a, b), y + ROOF_THICK, d / 2.0 + OVERHANG), shade, 0.04, seed + 70)
		x += v
		row += 1
