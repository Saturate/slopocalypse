class_name VoxWarehouse
extends VoxGenerator
## The BLÅGUL store: a big flat-roofed box clad in blue panels with a yellow band round the
## top, the name in blue block letters on a yellow sign standing on the front edge of the
## roof, a wide entrance under a yellow canopy at the front (-z) with a pavement and a car
## park of painted bays in front of it, and loading docks at the back (+z): a raised concrete
## dock outside with steps up, roller shutters (the first one rolled up), and a matching dock
## inside so the open door leads onto a floor. Inside it is one hall with steel columns and
## a polished concrete floor; the shelving and flat packs are their own pieces
## (`VoxShelving`, `VoxFlatPack`), placed by whoever stands the store up.
##
## Centred on the hall, standing on y 0. Every height that has to match its collision is
## snapped to whole voxels (`snap`), so the boxes in `collision` sit on what is drawn.

const BLUE := Color(0.07, 0.27, 0.56)
const YELLOW := Color(0.98, 0.8, 0.08)
const ROOF := Color(0.36, 0.37, 0.38)
const FLOOR := Color(0.6, 0.6, 0.57)
const INSIDE := Color(0.78, 0.78, 0.75)
const CONCRETE := Color(0.62, 0.61, 0.58)
const PAVING := Color(0.7, 0.68, 0.64)
const ASPHALT := Color(0.2, 0.2, 0.21)
const LINE := Color(0.88, 0.88, 0.85)
const SHUTTER := Color(0.55, 0.57, 0.58)
const BUMPER := Color(0.08, 0.08, 0.08)
const COLUMN := Color(0.3, 0.33, 0.38)
const GLASS := Color(0.12, 0.16, 0.2)
const UNIT := Color(0.66, 0.67, 0.66)
## Cladding panels, metres wide; every other one a shade darker.
const PANEL := 1.2
const WALL_THICK := 0.4
const ROOF_THICK := 0.5
const PARAPET := 0.8
## The yellow band: from this far below the top of the parapet, this tall.
const BAND_TOP := 0.4
const BAND := 1.4
const ENTRANCE := Vector2(7.0, 3.4)
const CANOPY_DEPTH := 3.0
## Glass either side of the doorway, metres along the front.
const SHOPFRONT := 3.0
const CANOPY_THICK := 0.5
## The canopy sits this far over the doorway and reaches this far past it each side.
const CANOPY_RISE := 0.3
const CANOPY_WIDEN := 1.0
const PAVEMENT := 3.0
const BAY := Vector2(2.5, 5.0)
const AISLE := 6.0
const DOCK_HEIGHT := 1.2
const DOCK_DEPTH := 3.0
## Shutters, one per dock, this far apart along the back.
const DOCK_PITCH := 4.5
const SHUTTER_SIZE := Vector2(3.0, 3.4)
## The open shutter rolled up to leave this much showing at the top.
const ROLLED := 0.6
const STEP_RUN := 0.35
const STEP_RISE := 0.3
const STEP_WIDTH := 1.4
const COLUMN_PITCH := 10.0
const COLUMN_SIZE := 0.4
const ROOF_UNITS := 3
const UNIT_SIZE := Vector3(3.0, 1.4, 2.0)
## The sign's letters, five cells wide and eleven tall (Å has its ring over the cap height of
## seven), `#` filled.
const GLYPHS := {
	"B": ["....", "....", "....", "....", "####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
	"L": ["....", "....", "....", "....", "#....", "#....", "#....", "#....", "#....", "#....", "#####"],
	"Å": [".###.", ".#.#.", ".###.", ".....", ".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"G": ["....", "....", "....", "....", ".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".###."],
	"U": ["....", "....", "....", "....", "#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
}
const NAME := "BLÅGUL"
const GLYPH_ROWS := 11
const GLYPH_COLS := 5
## The sign takes this share of the front's width, at most `MAX_CELL` metres a letter cell.
const SIGN_SHARE := 0.55
const MAX_CELL := 0.45


func title() -> String:
	return "BLÅGUL warehouse"


func params() -> Array[Dictionary]:
	return [
		seed_param(),
		param("width", "Width (m)", 24.0, 64.0, 1.0, 40.0),
		param("depth", "Depth (m)", 20.0, 48.0, 1.0, 30.0),
		param("height", "Height (m)", 7.0, 14.0, 0.5, 9.0),
		param("docks", "Loading docks", 1.0, 6.0, 1.0, 3.0),
		param("car_park", "Car park depth (m)", 0.0, 30.0, 1.0, 16.0),
		# Finer than this a big store with a deep car park outgrows the voxel grid's cap.
		voxel_param(0.25, 0.4, 0.25),
	]


## `x` metres to whole voxels, at least one.
static func snap(x: float, v: float) -> float:
	return maxf(roundf(x / v), 1.0) * v


## The hall's floor top: two voxels of slab.
static func floor_top(values: Dictionary) -> float:
	var p := VoxWarehouse.new().with_defaults(values)
	return float(p["voxel"]) * 2.0


static func dock_count(values: Dictionary) -> int:
	var p := VoxWarehouse.new().with_defaults(values)
	var room := float(p["width"]) - 6.0
	return clampi(int(p["docks"]), 1, maxi(1, int(room / DOCK_PITCH)))


## Shutter centres along x.
static func dock_xs(values: Dictionary) -> Array[float]:
	var n := dock_count(values)
	var out: Array[float] = []
	for i in n:
		out.append((float(i) - float(n - 1) / 2.0) * DOCK_PITCH)
	return out


## The whole piece on the ground (model space): the hall, the car park and pavement in front,
## the dock and its steps behind.
static func footprint(values: Dictionary) -> AABB:
	var p := VoxWarehouse.new().with_defaults(values)
	var w: float = p["width"]
	var d: float = p["depth"]
	var front := d / 2.0 + PAVEMENT + float(p["car_park"])
	var back := d / 2.0 + DOCK_DEPTH
	var h: float = float(p["height"]) + PARAPET
	return AABB(Vector3(-w / 2.0, 0.0, -front), Vector3(w, h, front + back))


## The side of one cell of the sign's letters, whole voxels, metres.
static func sign_cell(values: Dictionary) -> float:
	var p := VoxWarehouse.new().with_defaults(values)
	var v: float = p["voxel"]
	var cols := NAME.length() * (GLYPH_COLS + 1) + 1
	return maxf(floorf(minf(float(p["width"]) * SIGN_SHARE / cols, MAX_CELL) / v), 1.0) * v


## The sign's panel with its letters (model space).
static func sign_box(values: Dictionary) -> AABB:
	var p := VoxWarehouse.new().with_defaults(values)
	var cell := sign_cell(p)
	var cols := NAME.length() * (GLYPH_COLS + 1) + 1
	var size := Vector2(cols * cell, (GLYPH_ROWS + 2) * cell)
	var bottom := float(p["height"]) + PARAPET - BAND_TOP - BAND
	var z := -float(p["depth"]) / 2.0
	return AABB(Vector3(-size.x / 2.0, bottom, z - cell), Vector3(size.x, size.y, cell * 2.0))


## Collision boxes (model space): floor, walls round the entrance and the open shutter, roof
## and parapet, sign, canopy, pavement and car park, both docks and their steps, the columns
## and the roof units.
static func collision(values: Dictionary) -> Array[AABB]:
	var p := VoxWarehouse.new().with_defaults(values)
	var w: float = p["width"]
	var d: float = p["depth"]
	var h: float = p["height"]
	var v: float = p["voxel"]
	var floor_y := floor_top(p)
	var t := WALL_THICK
	var top := h + PARAPET
	var out: Array[AABB] = [AABB(Vector3(-w / 2.0, 0.0, -d / 2.0), Vector3(w, floor_y, d))]
	# Side walls, whole.
	out.append(AABB(Vector3(-w / 2.0, 0.0, -d / 2.0), Vector3(t, top, d)))
	out.append(AABB(Vector3(w / 2.0 - t, 0.0, -d / 2.0), Vector3(t, top, d)))
	# Front either side of the entrance and over it.
	var ex := ENTRANCE.x / 2.0
	var ey := floor_y + ENTRANCE.y
	out.append(AABB(Vector3(-w / 2.0, 0.0, -d / 2.0), Vector3(w / 2.0 - ex, top, t)))
	out.append(AABB(Vector3(ex, 0.0, -d / 2.0), Vector3(w / 2.0 - ex, top, t)))
	out.append(AABB(Vector3(-ex, ey, -d / 2.0), Vector3(ENTRANCE.x, top - ey, t)))
	# Back: solid but for the open shutter's gap.
	var dock_y := snap(DOCK_HEIGHT, v)
	var gap := dock_xs(p)[0]
	var gx := SHUTTER_SIZE.x / 2.0
	var gy := dock_y + SHUTTER_SIZE.y - ROLLED
	out.append(AABB(Vector3(-w / 2.0, 0.0, d / 2.0 - t), Vector3(gap - gx + w / 2.0, top, t)))
	out.append(AABB(Vector3(gap + gx, 0.0, d / 2.0 - t), Vector3(w / 2.0 - gap - gx, top, t)))
	out.append(AABB(Vector3(gap - gx, 0.0, d / 2.0 - t), Vector3(SHUTTER_SIZE.x, dock_y, t)))
	out.append(AABB(Vector3(gap - gx, gy, d / 2.0 - t), Vector3(SHUTTER_SIZE.x, top - gy, t)))
	out.append(AABB(Vector3(-w / 2.0, h - ROOF_THICK, -d / 2.0), Vector3(w, ROOF_THICK, d)))
	out.append(sign_box(p))
	out.append(AABB(Vector3(-ex - CANOPY_WIDEN, floor_y + ENTRANCE.y + CANOPY_RISE, -d / 2.0 - CANOPY_DEPTH), Vector3(ENTRANCE.x + CANOPY_WIDEN * 2.0, CANOPY_THICK, CANOPY_DEPTH)))
	for post: Vector3 in _canopy_posts(p):
		out.append(AABB(post - Vector3(0.15, 0.0, 0.15), Vector3(0.3, floor_y + ENTRANCE.y + CANOPY_RISE - post.y, 0.3)))
	out.append(AABB(Vector3(-w / 2.0, 0.0, -d / 2.0 - PAVEMENT), Vector3(w, floor_y, PAVEMENT)))
	var car_park: float = p["car_park"]
	if car_park > 0.0:
		out.append(AABB(Vector3(-w / 2.0, 0.0, -d / 2.0 - PAVEMENT - car_park), Vector3(w, v, car_park)))
	for box in _docks(p):
		out.append(box)
	for c: Vector2 in _columns(w, d):
		out.append(AABB(Vector3(c.x - COLUMN_SIZE / 2.0, floor_y, c.y - COLUMN_SIZE / 2.0), Vector3(COLUMN_SIZE, h - floor_y, COLUMN_SIZE)))
	for u: Vector3 in _units(p):
		out.append(AABB(Vector3(u.x - UNIT_SIZE.x / 2.0, h, u.z - UNIT_SIZE.z / 2.0), UNIT_SIZE))
	return out


## The docks outside and in, and the steps up to each, as boxes: the same in the model and
## its collision.
static func _docks(p: Dictionary) -> Array[AABB]:
	var d: float = p["depth"]
	var v: float = p["voxel"]
	var xs := dock_xs(p)
	var dock_y := snap(DOCK_HEIGHT, v)
	var x0 := xs[0] - DOCK_PITCH / 2.0
	var x1 := xs[xs.size() - 1] + DOCK_PITCH / 2.0
	var out: Array[AABB] = []
	out.append(AABB(Vector3(x0, 0.0, d / 2.0), Vector3(x1 - x0, dock_y, DOCK_DEPTH)))
	var inner := d / 2.0 - WALL_THICK - DOCK_DEPTH
	out.append(AABB(Vector3(x0, 0.0, inner), Vector3(x1 - x0, dock_y, DOCK_DEPTH)))
	# Steps: down from the outside dock's +x end, and from the inside one's -x end.
	var step := snap(STEP_RISE, v)
	var n := maxi(int(roundf(dock_y / step)), 2)
	for i in n - 1:
		var rise := dock_y - step * float(i + 1)
		out.append(AABB(Vector3(x1 + i * STEP_RUN, 0.0, d / 2.0 + DOCK_DEPTH - STEP_WIDTH), Vector3(STEP_RUN, rise, STEP_WIDTH)))
		out.append(AABB(Vector3(x0 - (i + 1) * STEP_RUN, 0.0, inner), Vector3(STEP_RUN, rise, STEP_WIDTH)))
	return out


## The canopy's two posts, at their feet on the pavement.
static func _canopy_posts(p: Dictionary) -> Array[Vector3]:
	var z := -float(p["depth"]) / 2.0 - CANOPY_DEPTH + 0.35
	var x := ENTRANCE.x / 2.0 + 0.6
	var y := floor_top(p)
	return [Vector3(-x, y, z), Vector3(x, y, z)]


## Column centres (x, z) on a grid inside the hall, none closer than half a pitch to a wall.
static func _columns(w: float, d: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var nx := maxi(int(w / COLUMN_PITCH) - 1, 0)
	var nz := maxi(int(d / COLUMN_PITCH) - 1, 0)
	for i in nx:
		for k in nz:
			var x := (float(i) - float(nx - 1) / 2.0) * COLUMN_PITCH
			var z := (float(k) - float(nz - 1) / 2.0) * COLUMN_PITCH
			out.append(Vector2(x, z))
	return out


## Roof unit centres, from the seed, clear of the sign and the edges.
static func _units(p: Dictionary) -> Array[Vector3]:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p["seed"]) + 7
	var w: float = p["width"]
	var d: float = p["depth"]
	var out: Array[Vector3] = []
	for i in ROOF_UNITS:
		var x := rng.randf_range(-w / 2.0 + 4.0, w / 2.0 - 4.0)
		var z := rng.randf_range(-d / 2.0 + 5.0, d / 2.0 - 4.0)
		out.append(Vector3(x, 0.0, z))
	return out


func build(values: Dictionary) -> VoxelModel:
	var p := with_defaults(values)
	var seed := int(p["seed"])
	var w: float = p["width"]
	var d: float = p["depth"]
	var h: float = p["height"]
	var v: float = p["voxel"]
	var car_park: float = p["car_park"]
	var floor_y := floor_top(p)
	var top := h + PARAPET
	var sign := sign_box(p)
	var foot := footprint(p)
	var reach := maxf(-foot.position.z, foot.end.z + 2.0)
	var m := new_model()
	m.setup(Vector3(w + v * 4.0, maxf(sign.end.y, h + UNIT_SIZE.y) + v * 4.0, reach * 2.0 + v * 4.0), v)
	var concrete := VoxMaterials.index_of("concrete")
	var metal := VoxMaterials.index_of("sheet_metal")
	m.set_material(concrete)
	m.fill_box(Vector3(-w / 2.0, 0.0, -d / 2.0), Vector3(w / 2.0, floor_y, d / 2.0), FLOOR, 0.0, seed)
	# Cladding panels down every wall, two shades so the seams read; flat colour so the
	# mesher can merge each panel into a few quads.
	m.set_material(metal)
	var x := -w / 2.0
	var k := 0
	while x < w / 2.0 - 0.001:
		var x1 := minf(x + PANEL, w / 2.0)
		var shade := BLUE if k % 2 == 0 else BLUE.darkened(0.08)
		m.fill_box(Vector3(x, 0.0, -d / 2.0), Vector3(x1, top, -d / 2.0 + WALL_THICK), shade, 0.0, seed)
		m.fill_box(Vector3(x, 0.0, d / 2.0 - WALL_THICK), Vector3(x1, top, d / 2.0), shade, 0.0, seed)
		x = x1
		k += 1
	var z := -d / 2.0
	k = 0
	while z < d / 2.0 - 0.001:
		var z1 := minf(z + PANEL, d / 2.0)
		var shade := BLUE if k % 2 == 0 else BLUE.darkened(0.08)
		m.fill_box(Vector3(-w / 2.0, 0.0, z), Vector3(-w / 2.0 + WALL_THICK, top, z1), shade, 0.0, seed)
		m.fill_box(Vector3(w / 2.0 - WALL_THICK, 0.0, z), Vector3(w / 2.0, top, z1), shade, 0.0, seed)
		z = z1
		k += 1
	# The yellow band round the outside, near the top.
	m.paint_box(Vector3(-w, top - BAND_TOP - BAND, -d), Vector3(w, top - BAND_TOP, d), YELLOW, 0.0, seed)
	m.set_material(concrete)
	m.fill_box(Vector3(-w / 2.0 + WALL_THICK, h - ROOF_THICK, -d / 2.0 + WALL_THICK), Vector3(w / 2.0 - WALL_THICK, h, d / 2.0 - WALL_THICK), ROOF, 0.0, seed)
	# Inside: pale walls and ceiling over the floor.
	var inner := Vector3(w / 2.0 - WALL_THICK, 0.0, d / 2.0 - WALL_THICK)
	m.paint_box(Vector3(-inner.x - v, floor_y, -inner.z - v), Vector3(inner.x + v, h - ROOF_THICK - v * 0.01, inner.z + v), INSIDE, 0.0, seed)
	m.paint_box(Vector3(-inner.x, h - ROOF_THICK, -inner.z), Vector3(inner.x, h - ROOF_THICK + v, inner.z), INSIDE, 0.0, seed)
	_entrance(m, p, floor_y, v, seed)
	_docks_drawn(m, p, v, seed)
	_car_park(m, p, floor_y, v, car_park)
	m.set_material(metal)
	for c: Vector2 in _columns(w, d):
		m.fill_box(Vector3(c.x - COLUMN_SIZE / 2.0, floor_y, c.y - COLUMN_SIZE / 2.0), Vector3(c.x + COLUMN_SIZE / 2.0, h - ROOF_THICK, c.y + COLUMN_SIZE / 2.0), COLUMN, 0.0, seed)
	for u: Vector3 in _units(p):
		m.fill_box(Vector3(u.x - UNIT_SIZE.x / 2.0, h, u.z - UNIT_SIZE.z / 2.0), Vector3(u.x + UNIT_SIZE.x / 2.0, h + UNIT_SIZE.y, u.z + UNIT_SIZE.z / 2.0), UNIT, 0.03, seed + 3)
		m.fill_cylinder(Vector3(u.x + UNIT_SIZE.x * 0.2, h + UNIT_SIZE.y, u.z), UNIT_SIZE.z * 0.3, v, BUMPER, 0.0, seed)
	_sign(m, p, sign, seed)
	return m


## The doorway through the front, its yellow frame, and the canopy over it on two posts.
func _entrance(m: VoxelModel, p: Dictionary, floor_y: float, v: float, seed: int) -> void:
	var d: float = p["depth"]
	var ex := ENTRANCE.x / 2.0
	var ey := floor_y + ENTRANCE.y
	var face := -d / 2.0
	m.carve_box(Vector3(-ex, floor_y, face - v), Vector3(ex, ey, face + WALL_THICK + v))
	# A shop front of dark glass either side of the doorway, so the entrance reads from afar.
	m.set_material(VoxMaterials.index_of("window_glass"))
	for side: float in [-1.0, 1.0]:
		var a := side * (ex + v * 2.0)
		var b := side * (ex + v * 2.0 + SHOPFRONT)
		m.carve_box(Vector3(minf(a, b), floor_y + v, face - v), Vector3(maxf(a, b), ey, face + WALL_THICK * 0.5))
		m.fill_box(Vector3(minf(a, b), floor_y + v, face + v * 0.5), Vector3(maxf(a, b), ey, face + v * 1.5), GLASS, 0.0, seed)
	m.set_material(VoxMaterials.index_of("sheet_metal"))
	m.fill_box(Vector3(-ex - v * 2.0, floor_y, face - v), Vector3(-ex, ey + v * 2.0, face), YELLOW, 0.0, seed)
	m.fill_box(Vector3(ex, floor_y, face - v), Vector3(ex + v * 2.0, ey + v * 2.0, face), YELLOW, 0.0, seed)
	m.fill_box(Vector3(-ex - v * 2.0, ey, face - v), Vector3(ex + v * 2.0, ey + v * 2.0, face), YELLOW, 0.0, seed)
	var cy := ey + CANOPY_RISE
	m.fill_box(Vector3(-ex - CANOPY_WIDEN, cy, face - CANOPY_DEPTH), Vector3(ex + CANOPY_WIDEN, cy + CANOPY_THICK, face), YELLOW, 0.0, seed)
	m.fill_box(Vector3(-ex - CANOPY_WIDEN, cy, face - CANOPY_DEPTH), Vector3(ex + CANOPY_WIDEN, cy + v, face), YELLOW.darkened(0.2), 0.0, seed)
	for post: Vector3 in _canopy_posts(p):
		m.fill_box(post - Vector3(0.15, 0.0, 0.15), Vector3(post.x + 0.15, cy, post.z + 0.15), BLUE.darkened(0.2), 0.0, seed)


## Docks, steps, shutters (the first rolled up and its doorway open) and bumpers.
func _docks_drawn(m: VoxelModel, p: Dictionary, v: float, seed: int) -> void:
	var d: float = p["depth"]
	var dock_y := snap(DOCK_HEIGHT, v)
	m.set_material(VoxMaterials.index_of("concrete"))
	for box in _docks(p):
		m.fill_box(box.position, box.end, CONCRETE, 0.0, seed)
	var back := d / 2.0
	var xs := dock_xs(p)
	m.set_material(VoxMaterials.index_of("sheet_metal"))
	for i in xs.size():
		var sx := xs[i]
		var gx := SHUTTER_SIZE.x / 2.0
		var y1 := dock_y + SHUTTER_SIZE.y
		m.carve_box(Vector3(sx - gx, dock_y, back - WALL_THICK - v), Vector3(sx + gx, y1, back + v))
		var rolled := i == 0
		var y0 := y1 - ROLLED if rolled else dock_y
		# Slats, every other one darker.
		var y := y0
		var slat := 0
		while y < y1 - 0.001:
			var ya := minf(y + v, y1)
			m.fill_box(Vector3(sx - gx, y, back - WALL_THICK * 0.5 - v * 0.5), Vector3(sx + gx, ya, back - WALL_THICK * 0.5 + v * 0.5), SHUTTER if slat % 2 == 0 else SHUTTER.darkened(0.12), 0.0, seed)
			y = ya
			slat += 1
		m.fill_box(Vector3(sx - gx - v, dock_y, back), Vector3(sx - gx, y1 + v, back + v), YELLOW, 0.0, seed)
		m.fill_box(Vector3(sx + gx, dock_y, back), Vector3(sx + gx + v, y1 + v, back + v), YELLOW, 0.0, seed)
		for side: float in [-1.0, 1.0]:
			var bx := sx + side * (gx - 0.3)
			m.fill_box(Vector3(bx - 0.2, dock_y - 0.6, back + DOCK_DEPTH), Vector3(bx + 0.2, dock_y - 0.1, back + DOCK_DEPTH + v), BUMPER, 0.0, seed)
	# A yellow edge along the outside dock.
	var x0 := xs[0] - DOCK_PITCH / 2.0
	var x1 := xs[xs.size() - 1] + DOCK_PITCH / 2.0
	m.paint_box(Vector3(x0, dock_y - v, back + DOCK_DEPTH - v), Vector3(x1, dock_y, back + DOCK_DEPTH), YELLOW, 0.0, seed)


## The pavement along the front, then asphalt with a row of bays on each side of an aisle.
func _car_park(m: VoxelModel, p: Dictionary, floor_y: float, v: float, depth: float) -> void:
	var w: float = p["width"]
	var d: float = p["depth"]
	var front := -d / 2.0
	m.set_material(VoxMaterials.index_of("concrete"))
	m.fill_box(Vector3(-w / 2.0, 0.0, front - PAVEMENT), Vector3(w / 2.0, floor_y, front), PAVING, 0.0, 0)
	if depth <= 0.0:
		return
	var z1 := front - PAVEMENT
	var z0 := z1 - depth
	m.fill_box(Vector3(-w / 2.0, 0.0, z0), Vector3(w / 2.0, v, z1), ASPHALT, 0.0, 0)
	# Bay rows: one against the pavement, one across the aisle if there is room.
	var rows: Array[float] = [z1 - BAY.y]
	if depth >= BAY.y * 2.0 + AISLE:
		rows.append(z1 - BAY.y * 2.0 - AISLE)
	for rz in rows:
		var bx := -w / 2.0 + 1.0
		while bx <= w / 2.0 - 1.0:
			m.paint_box(Vector3(bx - v * 0.5, 0.0, rz), Vector3(bx + v * 0.5, v, rz + BAY.y), LINE, 0.0, 0)
			bx += BAY.x


## The yellow sign on the roof's front edge, the name in blue cells standing proud of it, on
## two legs down to the roof behind.
func _sign(m: VoxelModel, p: Dictionary, sign: AABB, seed: int) -> void:
	var v: float = p["voxel"]
	var cell := sign_cell(p)
	m.set_material(VoxMaterials.index_of("sheet_metal"))
	var back := sign.position.z + cell
	m.fill_box(Vector3(sign.position.x, sign.position.y, back), Vector3(sign.end.x, sign.end.y, back + v * 2.0), YELLOW, 0.0, seed)
	# The front faces -z, so seen from the car park +x is on the left: letters go from +x.
	var x := sign.end.x - cell
	for letter in NAME:
		var rows: Array = GLYPHS[letter]
		for r in GLYPH_ROWS:
			var row: String = rows[r]
			for c in row.length():
				if row[c] != "#":
					continue
				var cx := x - (c + 1) * cell
				var cy := sign.end.y - cell - (r + 1) * cell
				m.fill_box(Vector3(cx, cy, back - v), Vector3(cx + cell, cy + cell, back), BLUE, 0.0, seed)
		x -= (GLYPH_COLS + 1) * cell
	# Legs behind it down onto the roof.
	for side: float in [-0.35, 0.35]:
		var lx := side * (sign.size.x / 2.0)
		m.fill_box(Vector3(lx - 0.15, float(p["height"]), back + v), Vector3(lx + 0.15, sign.end.y - cell, back + 1.0), BLUE.darkened(0.3), 0.0, seed)
