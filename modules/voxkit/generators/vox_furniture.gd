class_name VoxFurniture
extends RefCounted
## Furniture drawn into a voxel model, at the model's own voxel size (a building's rooms are
## furnished in the building's model). Each piece stands on the floor at `at`, the middle of
## its footprint, with its front towards `facing` (one of +X, -X, +Z, -Z). Its parts are
## boxes in the piece's own frame: x across its front (-width/2 to width/2), y up from the
## floor, z from its back (-depth/2) to its front (depth/2). A part thinner than a voxel is
## widened to one, so legs and screens never vanish; that can reach half a voxel past the
## footprint, which placement leaves room for.
##
## Sizes are footprints in metres: x across the front, y front to back.

const SOFA := Vector2(2.0, 0.9)
const COFFEE_TABLE := Vector2(1.1, 0.6)
const TV_BENCH := Vector2(1.6, 0.45)
const FLOOR_LAMP := Vector2(0.45, 0.45)
const DINING_TABLE := Vector2(1.6, 0.9)
const KITCHEN_TABLE := Vector2(0.9, 0.75)
const CHAIR := Vector2(0.45, 0.45)
const BOOKSHELF := Vector2(0.9, 0.35)
const WARDROBE := Vector2(1.2, 0.6)
const DOUBLE_BED := Vector2(1.6, 2.1)
const SINGLE_BED := Vector2(0.9, 2.0)
const NIGHTSTAND := Vector2(0.45, 0.4)
const DESK := Vector2(1.2, 0.6)
const COUNTER_DEPTH := 0.6
const FRIDGE := Vector2(0.6, 0.65)
const TOILET := Vector2(0.45, 0.7)
const BASIN := Vector2(0.55, 0.45)
const SHOWER := Vector2(0.9, 0.9)
const PLANT := Vector2(0.45, 0.45)
## Pieces taller than a window sill: they go where they don't cover a window.
const TALL := 0.9

const OAK := Color(0.72, 0.55, 0.36)
const TEAK := Color(0.5, 0.31, 0.18)
const WHITE := Color(0.93, 0.92, 0.89)
const BLACK := Color(0.08, 0.08, 0.09)
const SCREEN := Color(0.1, 0.13, 0.19)
const STEEL := Color(0.62, 0.63, 0.64)
const SHADE := Color(0.97, 0.9, 0.72)
const LINEN := Color(0.95, 0.94, 0.9)
const POT := Color(0.66, 0.35, 0.22)
const LEAVES := Color(0.22, 0.45, 0.2)
const PORCELAIN := Color(0.96, 0.96, 0.95)
const SHOWER_GLASS := Color(0.62, 0.72, 0.75)
## Wool sofas, duvets and books in muted Scandinavian colours.
const FABRICS := [Color(0.45, 0.47, 0.49), Color(0.72, 0.56, 0.22), Color(0.25, 0.38, 0.3), Color(0.2, 0.25, 0.38), Color(0.6, 0.38, 0.33)]
const BOOKS := [Color(0.6, 0.2, 0.15), Color(0.2, 0.3, 0.5), Color(0.85, 0.8, 0.65), Color(0.25, 0.4, 0.25), Color(0.15, 0.15, 0.15), Color(0.8, 0.55, 0.2)]


## Footprint size in the model's x and z for a piece of footprint `size` facing `facing`.
static func extent(size: Vector2, facing: Vector3) -> Vector2:
	return size if absf(facing.z) > 0.5 else Vector2(size.y, size.x)


## One box of a piece, `lo`..`hi` in the piece's frame.
static func part(m: VoxelModel, at: Vector3, facing: Vector3, lo: Vector3, hi: Vector3, colour: Color, jitter := 0.03) -> void:
	var v := m.voxel_size()
	var right := Vector3(facing.z, 0.0, -facing.x)
	var a := at + right * lo.x + Vector3.UP * lo.y + facing * lo.z
	var b := at + right * hi.x + Vector3.UP * hi.y + facing * hi.z
	var low := a.min(b)
	var high := a.max(b)
	for axis in 3:
		if high[axis] - low[axis] < v:
			var mid := (high[axis] + low[axis]) / 2.0
			low[axis] = mid - v / 2.0
			high[axis] = mid + v / 2.0
	m.fill_box(low, high, colour, jitter, 0)


static func sofa(m: VoxelModel, at: Vector3, facing: Vector3, fabric: Color) -> void:
	var w := SOFA.x / 2.0
	var d := SOFA.y / 2.0
	part(m, at, facing, Vector3(-w, 0.0, -d), Vector3(w, 0.42, d), fabric.darkened(0.1))
	part(m, at, facing, Vector3(-w, 0.42, -d), Vector3(w, 0.85, -d + 0.25), fabric)
	part(m, at, facing, Vector3(-w, 0.42, -d), Vector3(-w + 0.18, 0.62, d), fabric)
	part(m, at, facing, Vector3(w - 0.18, 0.42, -d), Vector3(w, 0.62, d), fabric)
	part(m, at, facing, Vector3(-w + 0.18, 0.42, -d + 0.25), Vector3(w - 0.18, 0.5, d - 0.03), fabric.lightened(0.08))


static func coffee_table(m: VoxelModel, at: Vector3, facing: Vector3) -> void:
	_table(m, at, facing, COFFEE_TABLE, 0.42, TEAK)


static func dining_table(m: VoxelModel, at: Vector3, facing: Vector3, size: Vector2, wood: Color) -> void:
	_table(m, at, facing, size, 0.74, wood)


static func _table(m: VoxelModel, at: Vector3, facing: Vector3, size: Vector2, height: float, wood: Color) -> void:
	var w := size.x / 2.0
	var d := size.y / 2.0
	part(m, at, facing, Vector3(-w, height - 0.05, -d), Vector3(w, height, d), wood)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var leg := Vector3(sx * (w - 0.08), 0.0, sz * (d - 0.08))
			part(m, at, facing, leg - Vector3(0.03, 0.0, 0.03), leg + Vector3(0.03, height - 0.05, 0.03), wood.darkened(0.15))


## A chair whose seat faces `facing` (so it faces a table when `facing` points at it).
static func chair(m: VoxelModel, at: Vector3, facing: Vector3, wood: Color) -> void:
	part(m, at, facing, Vector3(-0.21, 0.42, -0.2), Vector3(0.21, 0.47, 0.2), wood)
	part(m, at, facing, Vector3(-0.21, 0.47, -0.22), Vector3(0.21, 0.86, -0.17), wood)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var leg := Vector3(sx * 0.17, 0.0, sz * 0.16)
			part(m, at, facing, leg - Vector3(0.02, 0.0, 0.02), leg + Vector3(0.02, 0.42, 0.02), wood.darkened(0.15))


## A table with a chair either side along its length (and one at each end if `ends`). The
## table's length runs across `facing`.
static func table_with_chairs(m: VoxelModel, at: Vector3, facing: Vector3, size: Vector2, wood: Color, ends: bool) -> void:
	dining_table(m, at, facing, size, wood)
	var right := Vector3(facing.z, 0.0, -facing.x)
	var per_side := 2 if size.x >= 1.4 else 1
	for k in per_side:
		var along := 0.0 if per_side == 1 else (k - 0.5) * size.x * 0.5
		for side: float in [-1.0, 1.0]:
			var seat := at + right * along + facing * side * (size.y / 2.0 + 0.2)
			chair(m, seat, -facing * side, wood)
	if ends:
		for side: float in [-1.0, 1.0]:
			chair(m, at + right * side * (size.x / 2.0 + 0.2), -right * side, wood)


## Footprint of `table_with_chairs` across and along `facing`.
static func dining_extent(size: Vector2, ends: bool) -> Vector2:
	return Vector2(size.x + (1.0 if ends else 0.1), size.y + 1.0)


## A low bench with a flat screen standing on it.
static func tv(m: VoxelModel, at: Vector3, facing: Vector3, wood: Color) -> void:
	var w := TV_BENCH.x / 2.0
	var d := TV_BENCH.y / 2.0
	part(m, at, facing, Vector3(-w, 0.05, -d), Vector3(w, 0.45, d), wood)
	part(m, at, facing, Vector3(-w + 0.05, 0.0, -d + 0.05), Vector3(w - 0.05, 0.05, d - 0.05), BLACK)
	part(m, at, facing, Vector3(-0.1, 0.45, -0.1), Vector3(0.1, 0.52, 0.0), BLACK)
	part(m, at, facing, Vector3(-0.62, 0.52, -0.08), Vector3(0.62, 1.22, -0.02), BLACK)
	part(m, at, facing, Vector3(-0.58, 0.56, -0.04), Vector3(0.58, 1.18, 0.0), SCREEN, 0.0)


static func floor_lamp(m: VoxelModel, at: Vector3) -> void:
	part(m, at, Vector3.BACK, Vector3(-0.15, 0.0, -0.15), Vector3(0.15, 0.04, 0.15), BLACK)
	part(m, at, Vector3.BACK, Vector3(-0.02, 0.0, -0.02), Vector3(0.02, 1.4, 0.02), BLACK)
	part(m, at, Vector3.BACK, Vector3(-0.2, 1.35, -0.2), Vector3(0.2, 1.65, 0.2), SHADE, 0.0)


## A small lamp standing on something `lift` metres high.
static func table_lamp(m: VoxelModel, at: Vector3, lift: float) -> void:
	part(m, at, Vector3.BACK, Vector3(-0.07, lift, -0.07), Vector3(0.07, lift + 0.2, 0.07), WHITE)
	part(m, at, Vector3.BACK, Vector3(-0.14, lift + 0.2, -0.14), Vector3(0.14, lift + 0.38, 0.14), SHADE, 0.0)


## A pendant of stacked shades hanging from a ceiling at height `ceiling` above `at`.
static func pendant(m: VoxelModel, at: Vector3, ceiling: float, brass: bool) -> void:
	var colour := Color(0.75, 0.5, 0.28) if brass else WHITE
	# The cord widens to a whole voxel, so it takes the ceiling's colour and doesn't read as a rod.
	part(m, at, Vector3.BACK, Vector3(-0.01, ceiling - 0.6, -0.01), Vector3(0.01, ceiling, 0.01), WHITE.darkened(0.08), 0.0)
	part(m, at, Vector3.BACK, Vector3(-0.12, ceiling - 0.62, -0.12), Vector3(0.12, ceiling - 0.55, 0.12), colour, 0.0)
	part(m, at, Vector3.BACK, Vector3(-0.2, ceiling - 0.72, -0.2), Vector3(0.2, ceiling - 0.65, 0.2), colour, 0.0)
	part(m, at, Vector3.BACK, Vector3(-0.28, ceiling - 0.82, -0.28), Vector3(0.28, ceiling - 0.76, 0.28), colour, 0.0)


static func bookshelf(m: VoxelModel, at: Vector3, facing: Vector3, rng: RandomNumberGenerator) -> void:
	var w := BOOKSHELF.x / 2.0
	var d := BOOKSHELF.y / 2.0
	part(m, at, facing, Vector3(-w, 0.0, -d), Vector3(w, 1.9, -d + 0.04), WHITE)
	for sx: float in [-1.0, 1.0]:
		part(m, at, facing, Vector3(sx * w - 0.03, 0.0, -d), Vector3(sx * w + 0.03, 1.9, d), WHITE)
	var y := 0.0
	while y < 1.8:
		part(m, at, facing, Vector3(-w, y, -d), Vector3(w, y + 0.04, d), WHITE)
		# A row of books, each its own colour and height.
		var x := -w + 0.05
		while x < w - 0.1:
			var bw := rng.randf_range(0.08, 0.2)
			var bh := rng.randf_range(0.2, 0.32)
			part(m, at, facing, Vector3(x, y + 0.04, -d + 0.04), Vector3(minf(x + bw, w - 0.05), y + 0.04 + bh, d - 0.05), BOOKS[rng.randi() % BOOKS.size()], 0.05)
			x += bw
		y += 0.45


static func wardrobe(m: VoxelModel, at: Vector3, facing: Vector3, wood: Color) -> void:
	var w := WARDROBE.x / 2.0
	var d := WARDROBE.y / 2.0
	part(m, at, facing, Vector3(-w, 0.0, -d), Vector3(w, 2.1, d), wood)
	part(m, at, facing, Vector3(-0.01, 0.05, d - 0.02), Vector3(0.01, 2.05, d), wood.darkened(0.3), 0.0)
	for sx: float in [-1.0, 1.0]:
		part(m, at, facing, Vector3(sx * 0.08, 0.95, d - 0.02), Vector3(sx * 0.1, 1.25, d), STEEL, 0.0)


## A bed with its head against the wall behind it and its foot towards `facing`.
static func bed(m: VoxelModel, at: Vector3, facing: Vector3, size: Vector2, wood: Color, duvet: Color) -> void:
	var w := size.x / 2.0
	var d := size.y / 2.0
	part(m, at, facing, Vector3(-w, 0.0, -d), Vector3(w, 0.3, d), wood)
	part(m, at, facing, Vector3(-w, 0.0, -d), Vector3(w, 1.0, -d + 0.08), wood)
	part(m, at, facing, Vector3(-w + 0.03, 0.3, -d + 0.08), Vector3(w - 0.03, 0.5, d - 0.02), LINEN)
	part(m, at, facing, Vector3(-w, 0.45, -d + 0.65), Vector3(w, 0.58, d), duvet)
	var pillows := 2 if size.x > 1.2 else 1
	for k in pillows:
		var cx := 0.0 if pillows == 1 else (k - 0.5) * size.x * 0.5
		part(m, at, facing, Vector3(cx - 0.3, 0.5, -d + 0.12), Vector3(cx + 0.3, 0.64, -d + 0.5), WHITE)


static func nightstand(m: VoxelModel, at: Vector3, facing: Vector3, wood: Color) -> void:
	part(m, at, facing, Vector3(-NIGHTSTAND.x / 2.0, 0.0, -NIGHTSTAND.y / 2.0), Vector3(NIGHTSTAND.x / 2.0, 0.5, NIGHTSTAND.y / 2.0), wood)
	table_lamp(m, at, 0.5)


## A desk against a wall with a chair in front of it and a lamp on it.
static func desk(m: VoxelModel, at: Vector3, facing: Vector3, wood: Color) -> void:
	_table(m, at, facing, DESK, 0.74, wood)
	part(m, at, facing, Vector3(0.3, 0.74, -0.25), Vector3(0.42, 0.95, -0.15), BLACK)
	chair(m, at + facing * (DESK.y / 2.0 + 0.15), -facing, wood)


## A kitchen run `length` long: base cupboards, a worktop with a sink and a hob in it, and
## wall cupboards above.
static func counter(m: VoxelModel, at: Vector3, facing: Vector3, length: float, worktop: Color, upper: bool) -> void:
	var w := length / 2.0
	var d := COUNTER_DEPTH / 2.0
	part(m, at, facing, Vector3(-w, 0.0, -d), Vector3(w, 0.86, d - 0.03), WHITE)
	part(m, at, facing, Vector3(-w, 0.0, d - 0.1), Vector3(w, 0.1, d - 0.03), BLACK.lightened(0.2))
	part(m, at, facing, Vector3(-w, 0.86, -d), Vector3(w, 0.92, d), worktop)
	if length >= 1.2:
		part(m, at, facing, Vector3(-w + 0.15, 0.88, -d + 0.1), Vector3(-w + 0.6, 0.93, d - 0.1), STEEL, 0.0)
		part(m, at, facing, Vector3(w - 0.65, 0.9, -d + 0.05), Vector3(w - 0.1, 0.94, d - 0.05), BLACK, 0.0)
	if upper:
		part(m, at, facing, Vector3(-w, 1.45, -d), Vector3(w, 2.15, -d + 0.35), WHITE)


static func fridge(m: VoxelModel, at: Vector3, facing: Vector3) -> void:
	var w := FRIDGE.x / 2.0
	var d := FRIDGE.y / 2.0
	part(m, at, facing, Vector3(-w, 0.0, -d), Vector3(w, 1.85, d), WHITE)
	part(m, at, facing, Vector3(-w, 1.2, d - 0.02), Vector3(w, 1.22, d), STEEL, 0.0)
	part(m, at, facing, Vector3(w - 0.08, 0.8, d - 0.02), Vector3(w - 0.05, 1.6, d), STEEL, 0.0)


static func toilet(m: VoxelModel, at: Vector3, facing: Vector3) -> void:
	var d := TOILET.y / 2.0
	part(m, at, facing, Vector3(-0.18, 0.0, -d + 0.15), Vector3(0.18, 0.42, d), PORCELAIN, 0.0)
	part(m, at, facing, Vector3(-0.2, 0.3, -d), Vector3(0.2, 0.8, -d + 0.18), PORCELAIN, 0.0)


static func basin(m: VoxelModel, at: Vector3, facing: Vector3) -> void:
	var w := BASIN.x / 2.0
	var d := BASIN.y / 2.0
	part(m, at, facing, Vector3(-0.08, 0.0, -d), Vector3(0.08, 0.75, -d + 0.15), PORCELAIN, 0.0)
	part(m, at, facing, Vector3(-w, 0.75, -d), Vector3(w, 0.88, d), PORCELAIN, 0.0)
	part(m, at, facing, Vector3(-0.25, 1.1, -d), Vector3(0.25, 1.7, -d + 0.02), SHOWER_GLASS.lightened(0.2), 0.0)


static func shower(m: VoxelModel, at: Vector3, facing: Vector3) -> void:
	var w := SHOWER.x / 2.0
	var d := SHOWER.y / 2.0
	part(m, at, facing, Vector3(-w, 0.0, -d), Vector3(w, 0.06, d), PORCELAIN, 0.0)
	part(m, at, facing, Vector3(-w, 0.0, d - 0.03), Vector3(w * 0.2, 2.0, d), SHOWER_GLASS, 0.0)
	part(m, at, facing, Vector3(-0.08, 1.95, -d), Vector3(0.08, 2.0, -d + 0.25), STEEL, 0.0)


static func plant(m: VoxelModel, at: Vector3) -> void:
	part(m, at, Vector3.BACK, Vector3(-0.14, 0.0, -0.14), Vector3(0.14, 0.32, 0.14), POT)
	m.fill_ellipsoid(at + Vector3(0.0, 0.7, 0.0), Vector3(0.2, 0.38, 0.2), LEAVES, 0.15, 7)
