class_name VoxJetty
extends VoxGenerator
## A wooden jetty out over the water, built in sections that join end to end: a pair of
## round piles at every joint with a cross brace between them, a stringer down each side, a
## deck of boards laid across, a kerb along both edges, iron bollards on the deck edge every
## other joint and a steel ladder down the seaward end. It runs along z, shore end at -z and
## sea end at +z, centred on the origin, with the pile feet at y 0 (the sea bed): the deck
## stands `height` metres above them. `collision` sizes its boxes from the same parts;
## `ladder_box` is where someone climbs out of the water, facing `ladder_into`.

const LADDERS: Array[String] = ["No", "Yes"]
## One section, joint to joint, metres.
const SECTION := 3.0
const BOARD := Color(0.56, 0.45, 0.32)
const STRINGER := Color(0.4, 0.31, 0.22)
const PILE := Color(0.33, 0.27, 0.21)
## Piles darken and go green where the sea reaches them.
const WET := Color(0.17, 0.2, 0.15)
const KERB := Color(0.47, 0.37, 0.26)
const IRON := Color(0.14, 0.15, 0.16)
const STEEL := Color(0.6, 0.62, 0.6)
const BOARD_WIDTH := 0.2
const DECK_THICK := 0.1
const STRINGER_SIZE := Vector2(0.15, 0.25)
const PILE_RADIUS := 0.16
## Piles stand this far in from the deck's edge, metres.
const PILE_INSET := 0.15
const KERB_SIZE := Vector2(0.12, 0.12)
const BOLLARD_RADIUS := 0.14
const BOLLARD_HEIGHT := 0.45
const LADDER_WIDTH := 0.5
const RUNG := 0.3
const STILE := 0.06
## The ladder's stiles reach this far above the deck, to hold on to stepping off.
const LADDER_HANDLES := 0.8
## The ladder stands off the deck's end by this much, metres.
const LADDER_DEPTH := 0.1
## How far out from the ladder a climber can be and still be on it, metres.
const CLIMB_REACH := 0.75
## How far above the deck the climb reaches: a climber's feet clear the deck's edge there.
const CLIMB_OVER := 0.35


func title() -> String:
	return "Jetty"


func params() -> Array[Dictionary]:
	return [
		seed_param(),
		param("sections", "Sections", 1.0, 12.0, 1.0, 4.0),
		param("width", "Width (m)", 1.6, 4.0, 0.1, 2.4),
		param("height", "Deck height (m)", 1.0, 4.0, 0.1, 2.0),
		choice("ladder", "Ladder", LADDERS, 1),
		param("wear", "Wear", 0.0, 1.0, 0.05, 0.3),
		voxel_param(0.04, 0.12, 0.06),
	]


## End to end, metres.
static func length(values: Dictionary) -> float:
	var p := VoxJetty.new().with_defaults(values)
	return float(int(p["sections"])) * SECTION


## The top of the deck boards, metres above the pile feet.
static func deck_top(values: Dictionary) -> float:
	var p := VoxJetty.new().with_defaults(values)
	return float(p["height"])


## Collision boxes (model space): the deck, the kerbs, each pile and bollard, and the ladder.
static func collision(values: Dictionary) -> Array[AABB]:
	var p := VoxJetty.new().with_defaults(values)
	var half_l := length(p) / 2.0
	var w: float = p["width"]
	var h: float = p["height"]
	var under := DECK_THICK + STRINGER_SIZE.y
	var out: Array[AABB] = [AABB(Vector3(-w / 2.0, h - under, -half_l), Vector3(w, under, half_l * 2.0))]
	for side: float in [-1.0, 1.0]:
		var x := side * (w / 2.0 - KERB_SIZE.x / 2.0)
		out.append(AABB(Vector3(x - KERB_SIZE.x / 2.0, h, -half_l), Vector3(KERB_SIZE.x, KERB_SIZE.y, half_l * 2.0)))
	for at: Vector3 in _piles(p):
		out.append(AABB(Vector3(at.x - PILE_RADIUS, 0.0, at.z - PILE_RADIUS), Vector3(PILE_RADIUS * 2.0, h - under, PILE_RADIUS * 2.0)))
	for at: Vector3 in _bollards(p):
		out.append(AABB(Vector3(at.x - BOLLARD_RADIUS, h, at.z - BOLLARD_RADIUS), Vector3(BOLLARD_RADIUS * 2.0, BOLLARD_HEIGHT, BOLLARD_RADIUS * 2.0)))
	if int(p["ladder"]) == 1:
		out.append(AABB(Vector3(-LADDER_WIDTH / 2.0, 0.0, half_l), Vector3(LADDER_WIDTH, h, LADDER_DEPTH)))
	return out


## Where someone on the ladder is climbing it (model space): off the sea end, from the sea
## bed to a little over the deck. Empty without a ladder.
static func ladder_box(values: Dictionary) -> AABB:
	var p := VoxJetty.new().with_defaults(values)
	if int(p["ladder"]) != 1:
		return AABB()
	var h: float = p["height"]
	return AABB(Vector3(-LADDER_WIDTH / 2.0 - 0.15, 0.0, length(p) / 2.0), Vector3(LADDER_WIDTH + 0.3, h + CLIMB_OVER, LADDER_DEPTH + CLIMB_REACH))


## The way a climber faces to go up the ladder (model space): back toward the shore.
static func ladder_into() -> Vector3:
	return Vector3.FORWARD


## Pile centres on the sea bed (y 0): two at every joint.
static func _piles(p: Dictionary) -> Array[Vector3]:
	var half_l := float(int(p["sections"])) * SECTION / 2.0
	var x := float(p["width"]) / 2.0 - PILE_INSET - PILE_RADIUS
	var out: Array[Vector3] = []
	for i in int(p["sections"]) + 1:
		var z := clampf(-half_l + i * SECTION, -half_l + PILE_RADIUS, half_l - PILE_RADIUS)
		out.append(Vector3(-x, 0.0, z))
		out.append(Vector3(x, 0.0, z))
	return out


## Bollard centres on the deck edge: at every other joint, alternating sides, and always at
## the sea end on both sides, where a boat ties up.
static func _bollards(p: Dictionary) -> Array[Vector3]:
	var sections := int(p["sections"])
	var half_l := float(sections) * SECTION / 2.0
	var x := float(p["width"]) / 2.0 - KERB_SIZE.x - BOLLARD_RADIUS - 0.05
	var out: Array[Vector3] = []
	var end := half_l - BOLLARD_RADIUS - 0.35
	for side: float in [-1.0, 1.0]:
		out.append(Vector3(side * x, 0.0, end))
	var i := sections - 2
	var k := 0
	while i > 0:
		var side := -1.0 if k % 2 == 0 else 1.0
		out.append(Vector3(side * x, 0.0, -half_l + i * SECTION))
		i -= 2
		k += 1
	return out


func build(values: Dictionary) -> VoxelModel:
	var p := with_defaults(values)
	var seed := int(p["seed"])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var w: float = p["width"]
	var h: float = p["height"]
	var v: float = p["voxel"]
	var half_l := length(p) / 2.0
	var ladder := int(p["ladder"]) == 1
	var m := new_model()
	var reach := half_l + LADDER_DEPTH + v * 3.0
	m.setup(Vector3(w + v * 4.0, h + maxf(BOLLARD_HEIGHT, LADDER_HANDLES) + v * 4.0, reach * 2.0 + v * 2.0), v)
	m.set_material(VoxMaterials.index_of("wood"))
	var under := h - DECK_THICK - STRINGER_SIZE.y
	# Piles, wet and green from the sea bed up to a little under the stringers.
	var wet_top := under * 0.55
	for at: Vector3 in _piles(p):
		var shade := rng.randf_range(0.85, 1.08)
		m.fill_cylinder(Vector3(at.x, 0.0, at.z), PILE_RADIUS, under + v, PILE * shade, 0.06, seed + 1)
		m.paint_box(Vector3(at.x - PILE_RADIUS * 2.0, 0.0, at.z - PILE_RADIUS * 2.0), Vector3(at.x + PILE_RADIUS * 2.0, wet_top, at.z + PILE_RADIUS * 2.0), WET, 0.12, seed + 2)
	# A cross brace between each pair, and a cap beam across their heads.
	var piles := _piles(p)
	var brace_r := maxf(0.05, v * 0.75)
	for i in range(0, piles.size(), 2):
		var a := piles[i]
		var b := piles[i + 1]
		var low := under * 0.3
		var high := under - 0.15
		if high > low + 0.2:
			var flip := i % 4 == 0
			m.fill_capsule(Vector3(a.x, low if flip else high, a.z), Vector3(b.x, high if flip else low, b.z), brace_r, brace_r, STRINGER.darkened(0.1), 0.05, seed + 3)
		m.fill_box(Vector3(-w / 2.0 + PILE_INSET * 0.5, under - 0.15, a.z - 0.1), Vector3(w / 2.0 - PILE_INSET * 0.5, under, a.z + 0.1), STRINGER, 0.05, seed + 4)
	# Stringers along each side, on the pile heads.
	for side: float in [-1.0, 1.0]:
		var x := side * (w / 2.0 - PILE_INSET - PILE_RADIUS)
		m.fill_box(Vector3(x - STRINGER_SIZE.x / 2.0, under, -half_l), Vector3(x + STRINGER_SIZE.x / 2.0, under + STRINGER_SIZE.y, half_l), STRINGER, 0.05, seed + 5)
	# Deck boards across, each its own shade; with wear, a board here and there is dark and rotten.
	var z := -half_l
	var row := 0
	var wear: float = p["wear"]
	while z < half_l - 0.001:
		var z1 := minf(z + BOARD_WIDTH, half_l)
		var shade := BOARD * rng.randf_range(0.82, 1.08)
		if rng.randf() < wear * 0.25:
			shade = shade.darkened(0.25)
		m.fill_box(Vector3(-w / 2.0, h - DECK_THICK, z), Vector3(w / 2.0, h, z1), shade, 0.05, seed + 10 + row)
		# A thin gap between boards, carved a voxel deep.
		if z1 < half_l - 0.001:
			m.carve_box(Vector3(-w / 2.0 + KERB_SIZE.x, h - v * 1.01, z1 - v * 0.5), Vector3(w / 2.0 - KERB_SIZE.x, h + v, z1 + v * 0.5))
		z = z1
		row += 1
	for side: float in [-1.0, 1.0]:
		var x := side * (w / 2.0 - KERB_SIZE.x / 2.0)
		m.fill_box(Vector3(x - KERB_SIZE.x / 2.0, h, -half_l), Vector3(x + KERB_SIZE.x / 2.0, h + KERB_SIZE.y, half_l), KERB, 0.05, seed + 6)
	# Bollards: an iron post with a wider cap.
	m.set_material(VoxMaterials.index_of("sheet_metal"))
	for at: Vector3 in _bollards(p):
		m.fill_cylinder(Vector3(at.x, h, at.z), BOLLARD_RADIUS, BOLLARD_HEIGHT - 0.08, IRON, 0.04, seed + 7)
		m.fill_cylinder(Vector3(at.x, h + BOLLARD_HEIGHT - 0.1, at.z), BOLLARD_RADIUS + maxf(v, 0.04), 0.1, IRON.lightened(0.08), 0.04, seed + 7)
	if ladder:
		_ladder(m, half_l, h, v, seed)
	return m


## Two stiles from the sea bed to above the deck and a rung every `RUNG` metres, just off the
## sea end.
func _ladder(m: VoxelModel, half_l: float, h: float, v: float, seed: int) -> void:
	var z0 := half_l
	var z1 := half_l + LADDER_DEPTH
	var half := LADDER_WIDTH / 2.0
	var stile := maxf(STILE, v)
	for side: float in [-1.0, 1.0]:
		var x := side * half
		m.fill_box(Vector3(x - stile / 2.0, 0.0, z0), Vector3(x + stile / 2.0, h + LADDER_HANDLES, z1), STEEL, 0.04, seed)
	var y := RUNG
	while y < h:
		m.fill_box(Vector3(-half, y, z1 - maxf(v, 0.05)), Vector3(half, y + maxf(v, 0.04), z1), STEEL.darkened(0.1), 0.04, seed)
		y += RUNG
