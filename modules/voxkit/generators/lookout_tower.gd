class_name VoxLookoutTower
extends VoxGenerator
## A timber lookout tower: four square legs with girts and one slim diagonal brace per bay on
## every side (open enough to see through), a plank deck on top with a rail round it, an
## optional roof on posts, and a pale ladder up the front (-z) from the ground to a gap in the
## rail. Centred on its legs, standing on the origin. `ladder_box` is where someone climbs it,
## facing `ladder_into`.

const ROOFS: Array[String] = ["No", "Yes"]
const TIMBER := Color(0.6, 0.5, 0.37)
const DECK := Color(0.62, 0.52, 0.38)
const RAIL := Color(0.72, 0.64, 0.5)
const ROOF := Color(0.34, 0.3, 0.27)
const LEG := 0.18
const BRACE := 0.06
const DECK_THICK := 0.15
## The deck reaches this far past the legs, metres.
const DECK_OVERHANG := 0.2
const RAIL_BAR := 0.1
const LADDER_WIDTH := 0.6
const LADDER := Color(0.8, 0.72, 0.56)
const RUNG := 0.3
const STILE := 0.08
## The ladder's stiles reach this far above the deck, to hold on to stepping off.
const LADDER_HANDLES := 0.9
## The ladder stands off the deck's edge by this much, metres.
const LADDER_DEPTH := 0.12
## How far out from the ladder a climber can be and still be on it, metres.
const CLIMB_REACH := 0.75
## How far above the deck the climb reaches: a climber's feet clear the deck's edge there
## and step off onto it.
const CLIMB_OVER := 0.35
const ROOF_CLEAR := 2.3
const ROOF_OVERHANG := 0.3
const ROOF_THICK := 0.15


func title() -> String:
	return "Lookout tower"


func params() -> Array[Dictionary]:
	return [
		seed_param(),
		param("height", "Deck height (m)", 6.0, 8.0, 0.1, 7.0),
		param("width", "Width (m)", 2.4, 3.6, 0.1, 3.0),
		param("rail", "Rail height (m)", 0.9, 1.2, 0.05, 1.0),
		choice("roof", "Roof", ROOFS, 1),
		voxel_param(0.04, 0.15, 0.06),
	]


## The deck's outer edge from the middle, metres.
static func deck_half(width: float) -> float:
	return width / 2.0 + DECK_OVERHANG


## Collision boxes (model space): legs, deck, rail sides (the front one split round the
## ladder's gap), the ladder and the roof.
static func collision(values: Dictionary) -> Array[AABB]:
	var p := VoxLookoutTower.new().with_defaults(values)
	var h: float = p["height"]
	var w: float = p["width"]
	var rail: float = p["rail"]
	var roofed := int(p["roof"]) == 1
	var out: Array[AABB] = []
	var leg_top := h + (ROOF_CLEAR if roofed else rail)
	for c: Vector2 in _corners(w):
		out.append(AABB(Vector3(c.x - LEG / 2.0, 0.0, c.y - LEG / 2.0), Vector3(LEG, leg_top, LEG)))
	var d := deck_half(w)
	out.append(AABB(Vector3(-d, h - DECK_THICK, -d), Vector3(d * 2.0, DECK_THICK, d * 2.0)))
	var t := RAIL_BAR
	out.append(AABB(Vector3(-d, h, d - t), Vector3(d * 2.0, rail, t)))
	out.append(AABB(Vector3(-d, h, -d), Vector3(t, rail, d * 2.0)))
	out.append(AABB(Vector3(d - t, h, -d), Vector3(t, rail, d * 2.0)))
	var gap := LADDER_WIDTH / 2.0 + 0.2
	out.append(AABB(Vector3(-d, h, -d), Vector3(d - gap, rail, t)))
	out.append(AABB(Vector3(gap, h, -d), Vector3(d - gap, rail, t)))
	out.append(AABB(Vector3(-LADDER_WIDTH / 2.0, 0.0, -d - LADDER_DEPTH), Vector3(LADDER_WIDTH, h, LADDER_DEPTH)))
	if roofed:
		var r := d + ROOF_OVERHANG
		out.append(AABB(Vector3(-r, h + ROOF_CLEAR, -r), Vector3(r * 2.0, ROOF_THICK, r * 2.0)))
	return out


## Where someone on the ladder is climbing it (model space): in front of the ladder, from the
## ground to a little over the deck.
static func ladder_box(values: Dictionary) -> AABB:
	var p := VoxLookoutTower.new().with_defaults(values)
	var h: float = p["height"]
	var d := deck_half(p["width"])
	var front := -d - LADDER_DEPTH
	return AABB(Vector3(-LADDER_WIDTH / 2.0 - 0.15, 0.0, front - CLIMB_REACH), Vector3(LADDER_WIDTH + 0.3, h + CLIMB_OVER, CLIMB_REACH + LADDER_DEPTH))


## The way a climber faces to go up the ladder (model space): toward the tower.
static func ladder_into() -> Vector3:
	return Vector3.BACK


static func _corners(w: float) -> Array[Vector2]:
	var half := w / 2.0 - LEG / 2.0
	return [Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)]


func build(values: Dictionary) -> VoxelModel:
	var p := with_defaults(values)
	var seed := int(p["seed"])
	var h: float = p["height"]
	var w: float = p["width"]
	var rail: float = p["rail"]
	var v: float = p["voxel"]
	var roofed := int(p["roof"]) == 1
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var d := deck_half(w)
	var reach := (d + ROOF_OVERHANG + LADDER_DEPTH + v * 2.0) * 2.0
	var top := h + (ROOF_CLEAR + ROOF_THICK * 3.0 if roofed else rail + LADDER_HANDLES)
	var m := new_model()
	m.setup(Vector3(reach + v * 4.0, top + v * 4.0, reach + v * 4.0), v)
	m.set_material(VoxMaterials.index_of("wood"))
	var corners := _corners(w)
	var leg_top := h + (ROOF_CLEAR if roofed else rail)
	for c in corners:
		m.fill_box(Vector3(c.x - LEG / 2.0, 0.0, c.y - LEG / 2.0), Vector3(c.x + LEG / 2.0, leg_top, c.y + LEG / 2.0), TIMBER * rng.randf_range(0.9, 1.05), 0.06, seed)
	# Girts at the bottom, the middle and under the deck, crossed braces between them.
	var levels: Array[float] = [0.4, h * 0.5, h - DECK_THICK - BRACE]
	var brace_r := maxf(BRACE / 2.0, v * 0.75)
	for k in 4:
		var a := corners[k]
		var b := corners[(k + 1) % 4]
		for y in levels:
			m.fill_capsule(Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), brace_r, brace_r, TIMBER.darkened(0.08), 0.05, seed + k)
		# One diagonal per bay, leaning the other way each bay up, so the bays stay open.
		for i in levels.size() - 1:
			var y0 := levels[i]
			var y1 := levels[i + 1]
			var from := a if (i + k) % 2 == 0 else b
			var to := b if (i + k) % 2 == 0 else a
			m.fill_capsule(Vector3(from.x, y0, from.y), Vector3(to.x, y1, to.y), brace_r, brace_r, TIMBER.darkened(0.06), 0.05, seed + 10 + k)
	# The deck in planks running across x, each its own shade.
	var plank := 0.2
	var z := -d
	var row := 0
	while z < d - 0.001:
		m.fill_box(Vector3(-d, h - DECK_THICK, z), Vector3(d, h, minf(z + plank, d)), DECK * rng.randf_range(0.85, 1.08), 0.05, seed + 30 + row)
		z += plank
		row += 1
	_rail(m, d, h, rail, seed)
	_ladder(m, d, h, v, seed)
	if roofed:
		m.set_material(VoxMaterials.index_of("sheet_metal"))
		var r := d + ROOF_OVERHANG
		# A low hipped roof in three steps, each a little smaller.
		for k in 3:
			var s := r - k * 0.45
			var y := h + ROOF_CLEAR + k * ROOF_THICK
			m.fill_box(Vector3(-s, y, -s), Vector3(s, y + ROOF_THICK, s), ROOF.darkened(0.06 * k), 0.04, seed + 50 + k)
	return m


## Posts at the corners and the middle of each side, a top rail and a mid rail, open at the
## front where the ladder comes up.
func _rail(m: VoxelModel, d: float, h: float, rail: float, seed: int) -> void:
	var t := RAIL_BAR
	var gap := LADDER_WIDTH / 2.0 + 0.2
	for y in [h + rail - t, h + rail * 0.5]:
		var y0: float = y
		m.fill_box(Vector3(-d, y0, d - t), Vector3(d, y0 + t, d), RAIL, 0.05, seed)
		m.fill_box(Vector3(-d, y0, -d), Vector3(-d + t, y0 + t, d), RAIL, 0.05, seed)
		m.fill_box(Vector3(d - t, y0, -d), Vector3(d, y0 + t, d), RAIL, 0.05, seed)
		m.fill_box(Vector3(-d, y0, -d), Vector3(-gap, y0 + t, -d + t), RAIL, 0.05, seed)
		m.fill_box(Vector3(gap, y0, -d), Vector3(d, y0 + t, -d + t), RAIL, 0.05, seed)
	for x: float in [-d, 0.0, d - t]:
		for zz: float in [-d, 0.0, d - t]:
			if absf(zz + d) < 0.01 and absf(x) < gap:
				# The gap's own posts stand at its edges instead.
				continue
			if x == 0.0 and zz == 0.0:
				continue
			m.fill_box(Vector3(x, h, zz), Vector3(x + t, h + rail, zz + t), RAIL.darkened(0.05), 0.05, seed)
	for side: float in [-1.0, 1.0]:
		var gx := side * gap - (t if side > 0.0 else 0.0)
		m.fill_box(Vector3(gx, h, -d), Vector3(gx + t, h + rail, -d + t), RAIL.darkened(0.05), 0.05, seed)


## Two stiles from the ground to above the deck and a rung every `RUNG` metres, just off the
## front edge of the deck.
func _ladder(m: VoxelModel, d: float, h: float, v: float, seed: int) -> void:
	var z0 := -d - LADDER_DEPTH
	var z1 := -d
	var half := LADDER_WIDTH / 2.0
	var stile := maxf(STILE, v)
	for side: float in [-1.0, 1.0]:
		var x := side * half
		m.fill_box(Vector3(x - stile / 2.0, 0.0, z0), Vector3(x + stile / 2.0, h + LADDER_HANDLES, z1), LADDER, 0.04, seed)
	var y := RUNG
	while y < h:
		m.fill_box(Vector3(-half, y, z0), Vector3(half, y + maxf(v, 0.05), z0 + maxf(v, 0.06)), LADDER.darkened(0.08), 0.04, seed)
		y += RUNG
