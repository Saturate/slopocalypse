class_name VoxTunnel
extends VoxGenerator
## A road tunnel's mouth and first stretch: a concrete headwall around an arched opening,
## lined walls and roof with ring joints, walkways, wall lamps and a cable tray, ending in
## a cave-in that seals it. Built open at the bottom: the road and the ground are the floor.
##
## Local frame: x across (centred), y up with the tunnel floor at `FLOOR` above the model's
## origin (the walls reach below it so no gap shows on uneven ground), z along the tunnel
## with the portal at -length/2 and the cave-in ending at +length/2.

const FLOOR := 1.0
const CONCRETE := Color(0.58, 0.57, 0.53)
const JOINT := Color(0.42, 0.41, 0.38)
const GRIME := Color(0.33, 0.31, 0.28)
const SOOT := Color(0.3, 0.3, 0.3)
const WALKWAY := Color(0.64, 0.63, 0.59)
const KERB_PAINT := Color(0.86, 0.72, 0.2)
const COPING := Color(0.7, 0.69, 0.65)
const ROCK := Color(0.44, 0.41, 0.37)
const ROCK_DARK := Color(0.33, 0.31, 0.28)
const SOIL := Color(0.4, 0.31, 0.21)
const LAMP_HOUSING := Color(0.24, 0.24, 0.25)
const LAMP_LENS := Color(1.0, 0.86, 0.55)
const CABLE := Color(0.16, 0.16, 0.17)
const RING_SPACING := 3.0
const LAMP_SPACING := 6.0
const WALKWAY_WIDTH := 0.9
const WALKWAY_HEIGHT := 0.25
## The headwall stands this far proud of the portal and this far into the slope.
const HEADWALL_FRONT := 0.8
const HEADWALL_BACK := 0.2
## Headwall above the arch's crown, and how high its wings start where no ground says.
const HEADWALL_OVER_CROWN := 2.0


func title() -> String:
	return "Tunnel"


func params() -> Array[Dictionary]:
	return [
		seed_param(),
		param("width", "Inner width (m)", 6.0, 16.0, 0.2, 11.2),
		param("wall_height", "Wall height (m)", 2.5, 6.0, 0.1, 4.0),
		param("rise", "Arch rise (m)", 0.5, 4.0, 0.1, 1.5),
		param("length", "Length (m)", 8.0, 40.0, 1.0, 24.0),
		param("collapse", "Cave-in length (m)", 2.0, 12.0, 0.5, 6.0),
		param("lining", "Lining (m)", 0.25, 1.0, 0.05, 0.5),
		param("headwall_width", "Headwall width (m)", 8.0, 40.0, 1.0, 24.0),
		voxel_param(0.1, 0.5, 0.25),
	]


func build(values: Dictionary) -> VoxelModel:
	var p := with_defaults(values)
	return build_with_top(p, default_top(p))


## Headwall height above the floor at each x when there is no ground to follow: full height
## over the opening, stepping down towards the wings' ends.
static func default_top(p: Dictionary) -> Callable:
	var crown := float(p["wall_height"]) + float(p["rise"])
	var half_inner := float(p["width"]) / 2.0 + float(p["lining"])
	var half := float(p["headwall_width"]) / 2.0
	return func(x: float) -> float:
		var out := absf(x) - half_inner
		if out <= 0.0:
			return crown + HEADWALL_OVER_CROWN
		return lerpf(crown + HEADWALL_OVER_CROWN, 1.0, clampf(out / maxf(half - half_inner, 0.1), 0.0, 1.0))


## `top(x)` is the headwall's height above the floor at x; 0 or less leaves that column out.
func build_with_top(values: Dictionary, top: Callable) -> VoxelModel:
	var p := with_defaults(values)
	var seed := int(p["seed"])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var w: float = p["width"]
	var wh: float = p["wall_height"]
	var rise: float = p["rise"]
	var length: float = p["length"]
	var t: float = p["lining"]
	var v: float = p["voxel"]
	var hw: float = p["headwall_width"]
	var crown := wh + rise
	var tallest := crown + t
	var x := -hw / 2.0
	while x < hw / 2.0:
		tallest = maxf(tallest, float(top.call(x)))
		x += v
	var m := new_model()
	m.setup(Vector3(maxf(hw, w + t * 2.0) + v * 4.0, FLOOR + tallest + 2.5, length + HEADWALL_FRONT * 2.0 + v * 4.0), v)
	var front := -length / 2.0
	var back := length / 2.0
	_lining(m, p, front, back, seed)
	_walkways(m, w, front, back, seed)
	_details(m, p, front, back, seed)
	_headwall(m, p, top, front, seed)
	_cave_in(m, p, back, rng)
	return m


## The arch's inside height above the floor at x.
static func arch_height(p: Dictionary, x: float) -> float:
	var half := float(p["width"]) / 2.0
	var k := clampf(absf(x) / half, 0.0, 1.0)
	return float(p["wall_height"]) + float(p["rise"]) * sqrt(1.0 - k * k)


func _lining(m: VoxelModel, p: Dictionary, front: float, back: float, seed: int) -> void:
	var w: float = p["width"]
	var t: float = p["lining"]
	var v: float = p["voxel"]
	var crown := float(p["wall_height"]) + float(p["rise"])
	var half := w / 2.0
	m.fill_box(Vector3(-half - t, 0.0, front), Vector3(half + t, FLOOR + crown + t, back), CONCRETE, 0.08, seed)
	var x := -half
	while x < half - 0.001:
		m.carve_box(Vector3(x, 0.0, front - 1.0), Vector3(x + v, FLOOR + arch_height(p, x + v / 2.0), back + 1.0))
		x += v
	# Ring joints between the cast sections, then grime up from the road and soot streaks.
	var z := front + RING_SPACING
	while z < back:
		m.paint_box(Vector3(-half - t, 0.0, z), Vector3(half + t, FLOOR + crown + t, z + v), JOINT, 0.05, seed)
		z += RING_SPACING
	m.paint_box(Vector3(-half - t, 0.0, front), Vector3(half + t, FLOOR + 0.7, back), GRIME, 0.1, seed + 1)
	# Exhaust soot darkens the vault, so lamplight doesn't turn it a warm tan.
	m.paint_box(Vector3(-half, FLOOR + float(p["wall_height"]), front + 0.6), Vector3(half, FLOOR + crown + 0.01, back), SOOT, 0.12, seed + 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 9
	for i in int((back - front) * 0.8):
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var sz := rng.randf_range(front, back)
		var top := rng.randf_range(1.2, float(p["wall_height"]))
		m.paint_box(Vector3(side * half - t, FLOOR, sz), Vector3(side * half + t, FLOOR + top, sz + v * rng.randi_range(1, 3)), GRIME.lerp(CONCRETE, rng.randf_range(0.2, 0.6)), 0.1, seed + i)


func _walkways(m: VoxelModel, w: float, front: float, back: float, seed: int) -> void:
	var half := w / 2.0
	for side: float in [-1.0, 1.0]:
		var inner := side * (half - WALKWAY_WIDTH)
		m.fill_box(Vector3(minf(inner, side * half), 0.0, front), Vector3(maxf(inner, side * half), FLOOR + WALKWAY_HEIGHT, back), WALKWAY, 0.08, seed + 3)
		# A painted kerb edge, worn through in patches.
		m.paint_box(Vector3(inner - 0.13, FLOOR, front), Vector3(inner + 0.13, FLOOR + WALKWAY_HEIGHT + 0.01, back), KERB_PAINT, 0.15, seed + 4)
		var rng := RandomNumberGenerator.new()
		rng.seed = seed + 5 + int(side)
		var z := front
		while z < back:
			var gap := rng.randf_range(0.3, 1.2)
			m.paint_box(Vector3(inner - 0.13, FLOOR, z), Vector3(inner + 0.13, FLOOR + WALKWAY_HEIGHT + 0.01, z + gap), WALKWAY.darkened(0.1), 0.1, seed + 6)
			z += gap + rng.randf_range(1.0, 4.0)


## Wall lamps (alternating sides) and a cable tray along the left wall.
func _details(m: VoxelModel, p: Dictionary, front: float, back: float, seed: int) -> void:
	var half := float(p["width"]) / 2.0
	var wh: float = p["wall_height"]
	for at: Vector3 in lamp_positions(p):
		var side := signf(at.x)
		var y := at.y + FLOOR
		m.fill_box(Vector3(side * half - side * 0.25, y - 0.1, at.z - 0.35), Vector3(side * half, y + 0.15, at.z + 0.35), LAMP_HOUSING, 0.05, seed)
		var lens_x := side * half - side * 0.27
		m.fill_box(Vector3(minf(lens_x, lens_x + side * 0.1), y - 0.08, at.z - 0.3), Vector3(maxf(lens_x, lens_x + side * 0.1), y + 0.1, at.z + 0.3), LAMP_LENS, 0.0, seed)
	m.fill_box(Vector3(-half, FLOOR + wh - 0.75, front), Vector3(-half + 0.18, FLOOR + wh - 0.6, back), CABLE, 0.05, seed + 7)


## Where the lamps hang, relative to the floor's centre at the tunnel's middle.
static func lamp_positions(p: Dictionary) -> Array[Vector3]:
	var half := float(p["width"]) / 2.0
	var length: float = p["length"]
	var usable := length - float(p["collapse"]) - 1.0
	var out: Array[Vector3] = []
	var z := -length / 2.0 + 2.0
	var i := 0
	while z < -length / 2.0 + usable:
		var side := -1.0 if i % 2 == 0 else 1.0
		out.append(Vector3(side * half, float(p["wall_height"]) - 0.4, z))
		z += LAMP_SPACING
		i += 1
	return out


func _headwall(m: VoxelModel, p: Dictionary, top: Callable, front: float, seed: int) -> void:
	var v: float = p["voxel"]
	var hw: float = p["headwall_width"]
	var half := float(p["width"]) / 2.0
	var x := -hw / 2.0
	while x < hw / 2.0 - 0.001:
		var h := float(top.call(x + v / 2.0))
		if h > 0.0:
			m.fill_box(Vector3(x, 0.0, front - HEADWALL_FRONT), Vector3(x + v, FLOOR + h, front + HEADWALL_BACK), CONCRETE, 0.08, seed + 11)
			m.fill_box(Vector3(x, FLOOR + h, front - HEADWALL_FRONT - 0.1), Vector3(x + v, FLOOR + h + 0.2, front + HEADWALL_BACK), COPING, 0.05, seed + 12)
			m.paint_box(Vector3(x, 0.0, front - HEADWALL_FRONT - 0.2), Vector3(x + v, FLOOR + 0.6, front + HEADWALL_BACK), GRIME, 0.1, seed + 13)
		x += v
	# The opening, with a raised band over the arch.
	var frame := 0.35
	x = -half - frame
	while x < half + frame - 0.001:
		var cx := x + v / 2.0
		var inside := absf(cx) < half
		var arch := arch_height(p, clampf(cx, -half + 0.001, half - 0.001))
		if inside:
			m.fill_box(Vector3(x, FLOOR + arch, front - HEADWALL_FRONT - 0.2), Vector3(x + v, FLOOR + arch + frame, front - HEADWALL_FRONT), COPING, 0.05, seed + 14)
			m.carve_box(Vector3(x, 0.0, front - HEADWALL_FRONT - 1.0), Vector3(x + v, FLOOR + arch, front + HEADWALL_BACK + 0.01))
		x += v


## The far end: the roof came down. A rubble slope rising to the roof, a hole torn in the
## lining above it with rock showing through, and a solid plug behind so nothing shows past it.
func _cave_in(m: VoxelModel, p: Dictionary, back: float, rng: RandomNumberGenerator) -> void:
	var w: float = p["width"]
	var t: float = p["lining"]
	var v: float = p["voxel"]
	var collapse: float = p["collapse"]
	var crown := float(p["wall_height"]) + float(p["rise"])
	var half := w / 2.0
	var start := back - collapse
	m.fill_box(Vector3(-half - t, 0.0, back - 0.5), Vector3(half + t, FLOOR + crown + t, back), ROCK_DARK, 0.15, int(p["seed"]))
	# Torn roof: carve a ragged hole and push rock down through it.
	var hole := Vector3(rng.randf_range(-1.5, 1.0), FLOOR + crown, start + collapse * 0.55)
	m.carve_ellipsoid(hole, Vector3(half * 0.55, t * 3.0, collapse * 0.35))
	m.fill_blob(hole + Vector3(0, 0.4, 0), Vector3(half * 0.5, t * 2.5, collapse * 0.3), 0.3, 1.2, ROCK, 0.18, int(p["seed"]) + 20)
	# A core so there are no gaps to see through, then boulders and broken lining on it.
	var z := start
	while z < back:
		var h := rubble_height(p, z - start)
		if h > 0.05:
			m.fill_box(Vector3(-half, 0.0, z), Vector3(half, FLOOR + h * 0.75, z + v), SOIL, 0.2, int(p["seed"]) + 21)
		z += v
	for i in int(collapse * 9.0):
		var along := pow(rng.randf(), 0.6) * collapse
		var h := rubble_height(p, along)
		var r := rng.randf_range(0.35, 1.3)
		var at := Vector3(rng.randf_range(-half + 0.3, half - 0.3), FLOOR + h * rng.randf_range(0.35, 0.95), start + along)
		if rng.randf() < 0.3:
			var size := Vector3(rng.randf_range(0.5, 1.6), rng.randf_range(0.2, 0.5), rng.randf_range(0.5, 1.4))
			m.fill_box(at - size / 2.0, at + size / 2.0, CONCRETE.darkened(rng.randf_range(0.0, 0.2)), 0.1, i)
		else:
			var colour := ROCK.lerp(ROCK_DARK, rng.randf())
			m.fill_blob(at, Vector3(r, r * rng.randf_range(0.6, 0.9), r), 0.25, 1.5, colour, 0.15, int(p["seed"]) + 30 + i)


## How high the rubble stands `along` metres into the cave-in: a toe on the road rising to
## the roof at the back.
static func rubble_height(p: Dictionary, along: float) -> float:
	var collapse: float = p["collapse"]
	var crown := float(p["wall_height"]) + float(p["rise"])
	return crown * smoothstep(0.0, collapse * 0.85, along)


## Solid boxes (local frame) for collision: walls, roof, the headwall either side of and
## above the opening, the rubble as rising steps and the plug at the back. Walkways are left
## to the ground, which sits under them.
static func collision_boxes(values: Dictionary, top: Callable) -> Array[AABB]:
	var p := VoxTunnel.new().with_defaults(values)
	var w: float = p["width"]
	var t: float = p["lining"]
	var length: float = p["length"]
	var wh: float = p["wall_height"]
	var crown := wh + float(p["rise"])
	var half := w / 2.0
	var front := -length / 2.0
	var back := length / 2.0
	var out: Array[AABB] = []
	for side: float in [-1.0, 1.0]:
		var x0 := side * half if side > 0.0 else -half - t
		out.append(AABB(Vector3(x0, 0.0, front), Vector3(t, FLOOR + crown + t, length)))
		# The arch's haunch, so a grenade doesn't sail into the corner.
		var hx := side * half * 0.6 if side > 0.0 else -half
		out.append(AABB(Vector3(hx, FLOOR + wh + float(p["rise"]) * 0.6, front), Vector3(half * 0.4, crown - wh, length)))
	out.append(AABB(Vector3(-half - t, FLOOR + crown, front), Vector3(w + t * 2.0, t, length)))
	var hw: float = p["headwall_width"]
	var x := -hw / 2.0
	while x < hw / 2.0 - 0.001:
		var cx := x + 0.5
		var h := float(top.call(cx))
		if h > 0.0:
			var bottom := FLOOR + arch_height(p, cx) if absf(cx) < half else 0.0
			out.append(AABB(Vector3(x, bottom, front - HEADWALL_FRONT), Vector3(1.0, FLOOR + h - bottom, HEADWALL_FRONT + HEADWALL_BACK)))
		x += 1.0
	var collapse: float = p["collapse"]
	var start := back - collapse
	var step := collapse / 4.0
	for k in 4:
		var h := rubble_height(p, (k + 0.5) * step) * 0.85
		out.append(AABB(Vector3(-half, 0.0, start + k * step + step * 0.5), Vector3(w, FLOOR + h, step * (4 - k))))
	out.append(AABB(Vector3(-half, 0.0, back - 0.5), Vector3(w, FLOOR + crown, 0.5)))
	return out
