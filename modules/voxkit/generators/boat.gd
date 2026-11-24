class_name VoxBoat
extends VoxGenerator
## The small open boat that takes a squad and its gear across: a V-bottomed workboat with a
## flat transom at the stern (-z) and a fine bow (+z, the way the car points too), a raised
## sheer forward, a decked-over bow, an open well with a non-slip floor, a bench across the
## stern, a thwart forward, a centre console with a windscreen and a wheel, an outboard
## motor on the transom and fenders hung over the sides. Painted above the waterline,
## antifouling below it with a dark boot stripe between.
##
## The keel is at y 0, the floor of the well at `DECK`, the waterline at `WATERLINE`; centred
## on x and z. `deck_area` is the open floor players stand on; `collision` sizes its boxes
## from the same hull shape.

const PAINTS: Array[String] = ["White", "Navy", "Red", "Green", "Orange", "Grey"]
const HULLS := [Color(0.88, 0.88, 0.85), Color(0.13, 0.2, 0.34), Color(0.62, 0.15, 0.12), Color(0.18, 0.36, 0.26), Color(0.88, 0.45, 0.12), Color(0.5, 0.52, 0.53)]
const CONSOLES: Array[String] = ["No", "Yes"]
const ANTIFOULING := Color(0.42, 0.13, 0.1)
const BOOT := Color(0.12, 0.12, 0.13)
const RUB_RAIL := Color(0.16, 0.16, 0.17)
const FLOOR := Color(0.62, 0.62, 0.58)
const INSIDE := Color(0.82, 0.82, 0.78)
const SEAT := Color(0.56, 0.44, 0.3)
const MOTOR := Color(0.14, 0.15, 0.16)
const MOTOR_STRIPE := Color(0.85, 0.85, 0.82)
const FENDER := Color(0.9, 0.9, 0.88)
const GLASS := Color(0.3, 0.4, 0.45)
const STEEL := Color(0.62, 0.64, 0.64)
const LINE := Color(0.2, 0.25, 0.4)
## Keel to the floor of the well, and keel to the waterline, metres.
const DECK := 0.45
const WATERLINE := 0.4
## Keel to the top of the sides at the stern; the sheer rises by `SHEER_RISE` to the bow.
const GUNWALE := 1.1
const SHEER_RISE := 0.25
## The hull's skin; at least two voxels are drawn, so the inside paint never shows outside.
const HULL_THICK := 0.12
## The bow is decked over from this share of the length (from the stern) forward.
const FOREDECK := 0.8
## How far up the side (as a share of its height) the bottom's V turns into the topsides.
const CHINE := 0.35
## The transom is this share of the widest beam.
const TRANSOM := 0.86
const CONSOLE_SIZE := Vector3(0.7, 1.0, 0.6)
const SEAT_HEIGHT := 0.42
const SEAT_DEPTH := 0.4
## The thwart (a seat across the well) stands at this share of the length from the stern.
const THWART := 0.72
const THWART_DEPTH := 0.3
const MOTOR_SIZE := Vector3(0.42, 0.55, 0.5)
## How many boxes the hull's collision takes along the open well.
const SEGMENTS := 8


func title() -> String:
	return "Boat"


func params() -> Array[Dictionary]:
	return [
		seed_param(),
		choice("paint", "Hull colour", PAINTS, 1),
		param("length", "Length (m)", 5.0, 8.0, 0.1, 6.5),
		param("beam", "Beam (m)", 2.0, 3.0, 0.05, 2.4),
		choice("console", "Console", CONSOLES, 1),
		voxel_param(0.04, 0.12, 0.06),
	]


## Half the beam at share `t` of the length from the stern, metres: the transom, widest just
## aft of the middle, then curving in to the stem.
static func half_width(beam: float, t: float) -> float:
	var half := beam / 2.0
	if t < 0.5:
		return half * lerpf(TRANSOM, 1.0, smoothstep(0.0, 0.5, t))
	var f := (t - 0.5) / 0.5
	return maxf(half * sqrt(maxf(0.0, 1.0 - f * f)), 0.06)


## Height of the keel at share `t`: flat aft, sweeping up into the bow.
static func keel(t: float) -> float:
	return 0.0 if t < 0.6 else pow((t - 0.6) / 0.4, 2.0) * (DECK + 0.1)


## Height of the top of the sides at share `t`.
static func sheer(t: float) -> float:
	return GUNWALE + SHEER_RISE * pow(maxf(0.0, (t - 0.5) / 0.5), 2.0)


## The hull's half width at height `y` over the keel, at share `t`: narrow at the keel, flaring
## out to the chine, then nearly upright to the top.
static func section(beam: float, t: float, y: float) -> float:
	var k := keel(t)
	var top := sheer(t)
	var s := clampf((y - k) / maxf(top - k, 0.01), 0.0, 1.0)
	var f := lerpf(0.3, 0.92, s / CHINE) if s < CHINE else lerpf(0.92, 1.0, (s - CHINE) / (1.0 - CHINE))
	return half_width(beam, t) * f


## The open floor of the well players stand on (model space), from the stern bench to the
## thwart, between the sides; its top is at `DECK`. The console (`console_box`) stands in it.
## `DECK` is not snapped to the voxel, so the drawn floor may sit up to half a voxel off it.
static func deck_area(values: Dictionary) -> AABB:
	var p := VoxBoat.new().with_defaults(values)
	var l: float = p["length"]
	var b: float = p["beam"]
	var z0 := -l / 2.0 + HULL_THICK + SEAT_DEPTH
	var z1 := -l / 2.0 + l * THWART - THWART_DEPTH / 2.0
	# As narrow as the narrowest collision segment it reaches into, so it is all clear floor.
	var hw := INF
	for i in SEGMENTS:
		var t0 := FOREDECK * float(i) / SEGMENTS
		var t1 := FOREDECK * float(i + 1) / SEGMENTS
		if -l / 2.0 + l * t0 < z1:
			hw = minf(hw, minf(section(b, t0, DECK), section(b, t1, DECK)))
	hw -= HULL_THICK
	return AABB(Vector3(-hw, 0.0, z0), Vector3(hw * 2.0, DECK, z1 - z0))


## Collision boxes (model space): the hull under the floor and its two sides as a box each
## per segment along the well, the decked bow in a few steps, the transom, the stern bench,
## the thwart, the console and the motor.
static func collision(values: Dictionary) -> Array[AABB]:
	var p := VoxBoat.new().with_defaults(values)
	var l: float = p["length"]
	var b: float = p["beam"]
	var stern := -l / 2.0
	var out: Array[AABB] = []
	for i in SEGMENTS:
		var t0 := FOREDECK * float(i) / SEGMENTS
		var t1 := FOREDECK * float(i + 1) / SEGMENTS
		var z0 := stern + l * t0
		var z1 := stern + l * t1
		var inner := minf(section(b, t0, DECK), section(b, t1, DECK))
		var outer := maxf(half_width(b, t0), half_width(b, t1))
		var top := maxf(sheer(t0), sheer(t1))
		out.append(AABB(Vector3(-inner, 0.0, z0), Vector3(inner * 2.0, DECK, z1 - z0)))
		for side: float in [-1.0, 1.0]:
			var x_in := side * (inner - HULL_THICK)
			var x_out := side * outer
			out.append(AABB(Vector3(minf(x_in, x_out), 0.0, z0), Vector3(absf(x_out - x_in), top, z1 - z0)))
	var steps := 3
	for i in steps:
		var t0 := lerpf(FOREDECK, 1.0, float(i) / steps)
		var t1 := lerpf(FOREDECK, 1.0, float(i + 1) / steps)
		var hw := half_width(b, t0)
		var k := keel(t1)
		out.append(AABB(Vector3(-hw, k, stern + l * t0), Vector3(hw * 2.0, sheer(t1) - k, l * (t1 - t0))))
	out.append(AABB(Vector3(-half_width(b, 0.0), 0.0, stern), Vector3(half_width(b, 0.0) * 2.0, GUNWALE, HULL_THICK)))
	var bench := section(b, 0.05, DECK + SEAT_HEIGHT) - HULL_THICK
	out.append(AABB(Vector3(-bench, DECK, stern + HULL_THICK), Vector3(bench * 2.0, SEAT_HEIGHT, SEAT_DEPTH)))
	var thwart := section(b, THWART, DECK + SEAT_HEIGHT) - HULL_THICK
	out.append(AABB(Vector3(-thwart, DECK + SEAT_HEIGHT - 0.06, stern + l * THWART - THWART_DEPTH / 2.0), Vector3(thwart * 2.0, 0.06, THWART_DEPTH)))
	if int(p["console"]) == 1:
		out.append(console_box(l))
	out.append(_motor_box(l))
	return out


static func console_box(l: float) -> AABB:
	var z := -l / 2.0 + l * 0.42
	return AABB(Vector3(-CONSOLE_SIZE.x / 2.0, DECK, z - CONSOLE_SIZE.z / 2.0), CONSOLE_SIZE)


## The motor's cowling over the transom and its leg down past the keel line.
static func _motor_box(l: float) -> AABB:
	var stern := -l / 2.0
	return AABB(Vector3(-MOTOR_SIZE.x / 2.0, 0.0, stern - MOTOR_SIZE.z), Vector3(MOTOR_SIZE.x, GUNWALE + MOTOR_SIZE.y, MOTOR_SIZE.z))


func build(values: Dictionary) -> VoxelModel:
	var p := with_defaults(values)
	var seed := int(p["seed"])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var l: float = p["length"]
	var b: float = p["beam"]
	var v: float = p["voxel"]
	var hull: Color = HULLS[clampi(int(p["paint"]), 0, HULLS.size() - 1)]
	var stern := -l / 2.0
	var m := new_model()
	m.setup(Vector3(b + 0.6 + v * 4.0, GUNWALE + SHEER_RISE + MOTOR_SIZE.y + 0.4 + v * 4.0, l + MOTOR_SIZE.z * 2.0 + v * 4.0), v)
	m.set_material(VoxMaterials.index_of("sheet_metal"))
	# The hull slice by slice from stern to stem, solid up to the floor of the well.
	var z := stern
	while z < -stern - 0.001:
		var t := (z + v * 0.5 - stern) / l
		var k := keel(t)
		var top := sheer(t)
		var y := floorf(k / v) * v
		while y < top:
			var hw := section(b, t, y + v * 0.5)
			var colour := hull
			if y + v * 0.5 < WATERLINE - 0.06:
				colour = ANTIFOULING
			elif y + v * 0.5 < WATERLINE + 0.04:
				colour = BOOT
			elif y + v * 0.5 > top - 0.09:
				colour = RUB_RAIL
			m.fill_box(Vector3(-hw, maxf(y, k), z), Vector3(hw, minf(y + v, top), z + v), colour, 0.03, seed)
			y += v
		z += v
	# Hollow out the well above the floor, back to the transom and forward to the foredeck.
	z = stern + HULL_THICK
	var bow := stern + l * FOREDECK
	while z < bow:
		var t := (z + v * 0.5 - stern) / l
		var y := DECK
		var top := sheer(t) + v
		while y < top:
			var hw := section(b, t, minf(y + v * 0.5, sheer(t))) - maxf(HULL_THICK, v * 2.0)
			if hw > v:
				m.carve_box(Vector3(-hw, y, z), Vector3(hw, y + v, z + v))
				if y == DECK:
					# The non-slip floor, only as wide as the well so the outside stays painted.
					m.paint_box(Vector3(-hw, DECK - v, z), Vector3(hw, DECK, z + v), FLOOR, 0.1, seed + 2)
				# The inside skin lighter than the paint outside: one voxel in from the carve.
				m.paint_box(Vector3(-hw - v * 0.99, y, z), Vector3(hw + v * 0.99, y + v, z + v), INSIDE, 0.03, seed + 1)
			y += v
		z += v
	# The foredeck's top.
	var fz := bow
	while fz < -stern:
		var t := (fz + v * 0.5 - stern) / l
		var top := sheer(t)
		m.paint_box(Vector3(-b, top - v, fz), Vector3(b, top, fz + v), INSIDE, 0.03, seed + 3)
		fz += v
	_seats(m, l, b, v, seed)
	if int(p["console"]) == 1:
		_console(m, l, v, seed)
	_motor(m, l, v, seed)
	_fenders(m, l, b, v, seed)
	# A bow eye and two cleats aft.
	m.fill_box(Vector3(-0.04, sheer(1.0) - 0.15, -stern - v * 2.0), Vector3(0.04, sheer(1.0) + 0.02, -stern), STEEL, 0.02, seed)
	for side: float in [-1.0, 1.0]:
		var x := side * (half_width(b, 0.1) - HULL_THICK * 0.5)
		m.fill_box(Vector3(x - 0.03, GUNWALE, stern + l * 0.1 - 0.08), Vector3(x + 0.03, GUNWALE + maxf(v, 0.04), stern + l * 0.1 + 0.08), STEEL, 0.02, seed)
	return m


## A bench across the stern, a thwart forward, both in varnished wood.
func _seats(m: VoxelModel, l: float, b: float, v: float, seed: int) -> void:
	m.set_material(VoxMaterials.index_of("wood"))
	var stern := -l / 2.0
	# Seats stop at the inside of the skin, so they never show through the hull.
	var skin := maxf(HULL_THICK, v * 2.0)
	var bench := section(b, 0.05, DECK + SEAT_HEIGHT) - skin
	m.fill_box(Vector3(-bench, DECK, stern + HULL_THICK), Vector3(bench, DECK + SEAT_HEIGHT, stern + HULL_THICK + SEAT_DEPTH), SEAT.darkened(0.15), 0.05, seed + 10)
	m.fill_box(Vector3(-bench, DECK + SEAT_HEIGHT - 0.06, stern + HULL_THICK), Vector3(bench, DECK + SEAT_HEIGHT, stern + HULL_THICK + SEAT_DEPTH + 0.04), SEAT, 0.05, seed + 11)
	var thwart := section(b, THWART, DECK + SEAT_HEIGHT) - skin
	var tz := stern + l * THWART
	m.fill_box(Vector3(-thwart, DECK + SEAT_HEIGHT - 0.06, tz - THWART_DEPTH / 2.0), Vector3(thwart, DECK + SEAT_HEIGHT, tz + THWART_DEPTH / 2.0), SEAT, 0.05, seed + 12)
	m.fill_box(Vector3(-0.04, DECK, tz - 0.04), Vector3(0.04, DECK + SEAT_HEIGHT, tz + 0.04), SEAT.darkened(0.2), 0.05, seed + 12)
	m.set_material(VoxMaterials.index_of("sheet_metal"))


## A centre console: a box with a sloped top, a windscreen and a wheel on its aft face.
func _console(m: VoxelModel, l: float, v: float, seed: int) -> void:
	var box := console_box(l)
	var lo := box.position
	var hi := box.end
	m.fill_box(lo, Vector3(hi.x, hi.y - 0.15, hi.z), INSIDE.darkened(0.05), 0.03, seed + 20)
	m.fill_box(Vector3(lo.x, hi.y - 0.15, lo.z + 0.2), Vector3(hi.x, hi.y, hi.z), INSIDE.darkened(0.05), 0.03, seed + 20)
	m.fill_box(Vector3(lo.x + 0.08, hi.y - 0.2, lo.z - v), Vector3(hi.x - 0.08, hi.y - 0.12, lo.z), BOOT, 0.0, seed)
	m.set_material(VoxMaterials.index_of("window_glass"))
	m.fill_box(Vector3(lo.x - 0.02, hi.y, hi.z - v * 1.5), Vector3(hi.x + 0.02, hi.y + 0.35, hi.z), GLASS, 0.0, seed)
	m.set_material(VoxMaterials.index_of("sheet_metal"))
	# The wheel, facing aft toward whoever stands at it.
	var c := Vector3(0.0, hi.y - 0.32, lo.z - v * 1.5)
	var r := 0.16
	for i in 12:
		var a0 := TAU * i / 12.0
		var a1 := TAU * (i + 1) / 12.0
		m.fill_capsule(c + Vector3(cos(a0), sin(a0), 0.0) * r, c + Vector3(cos(a1), sin(a1), 0.0) * r, 0.025, 0.025, BOOT, 0.0, seed)
	m.fill_box(c - Vector3(0.03, 0.03, 0.0), c + Vector3(0.03, 0.03, v * 1.5), STEEL, 0.0, seed)


## An outboard on the transom: clamp bracket, a cowling with a pale stripe, the leg down to
## below the keel line with a cavitation plate and a propeller.
func _motor(m: VoxelModel, l: float, v: float, seed: int) -> void:
	var stern := -l / 2.0
	var box := _motor_box(l)
	var zc := stern - MOTOR_SIZE.z / 2.0
	var hx := MOTOR_SIZE.x / 2.0
	m.fill_box(Vector3(-0.1, GUNWALE - 0.25, stern - 0.12), Vector3(0.1, GUNWALE + 0.05, stern), MOTOR.lightened(0.1), 0.03, seed + 30)
	m.fill_box(Vector3(-hx, GUNWALE + 0.05, box.position.z), Vector3(hx, box.end.y, box.end.z - 0.05), MOTOR, 0.03, seed + 30)
	m.fill_box(Vector3(-hx * 0.85, box.end.y, box.position.z + 0.05), Vector3(hx * 0.85, box.end.y + v, box.end.z - 0.1), MOTOR, 0.03, seed + 30)
	m.paint_box(Vector3(-hx - v, GUNWALE + 0.3, box.position.z - v), Vector3(hx + v, GUNWALE + 0.36, box.end.z), MOTOR_STRIPE, 0.0, seed)
	m.fill_box(Vector3(-0.07, 0.1, zc - 0.1), Vector3(0.07, GUNWALE + 0.05, zc + 0.1), MOTOR.lightened(0.05), 0.03, seed + 31)
	m.fill_box(Vector3(-0.2, 0.28, zc - 0.2), Vector3(0.2, 0.28 + maxf(v, 0.04), zc + 0.12), MOTOR, 0.03, seed + 31)
	m.fill_box(Vector3(-0.12, 0.08, zc - 0.03), Vector3(0.12, 0.2, zc + 0.03), STEEL.darkened(0.3), 0.03, seed + 32)
	m.fill_box(Vector3(-0.03, 0.03, zc - 0.03), Vector3(0.03, 0.25, zc + 0.03), STEEL.darkened(0.3), 0.03, seed + 32)


## Two fenders hung over each side amidships.
func _fenders(m: VoxelModel, l: float, b: float, v: float, seed: int) -> void:
	var stern := -l / 2.0
	for t: float in [0.3, 0.55]:
		var z := stern + l * t
		for side: float in [-1.0, 1.0]:
			var x := side * (half_width(b, t) + 0.1)
			m.fill_capsule(Vector3(x, WATERLINE + 0.2, z), Vector3(x, WATERLINE + 0.45, z), 0.09, 0.09, FENDER, 0.03, seed + 40)
			# Its line up to the gunwale and over it.
			var edge := side * half_width(b, t)
			m.fill_box(Vector3(x - v * 0.5, WATERLINE + 0.45, z - v * 0.5), Vector3(x + v * 0.5, sheer(t) + v, z + v * 0.5), LINE, 0.0, seed)
			m.fill_box(Vector3(minf(x, edge) - v * 0.5, sheer(t), z - v * 0.5), Vector3(maxf(x, edge) + v * 0.5, sheer(t) + v, z + v * 0.5), LINE, 0.0, seed)
