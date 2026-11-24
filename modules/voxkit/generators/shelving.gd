class_name VoxShelving
extends VoxGenerator
## Warehouse shelving as the BLÅGUL store has it: a run of bays of steel pallet racking, blue
## upright frames with diagonal lacing and orange beams, a chipboard deck on each level, and
## flat-pack boxes stacked on the decks (how full is `fill`). The run goes along x, centred,
## the frames standing on y 0. `collision` gives each upright frame and each level's deck.

const UPRIGHT := Color(0.12, 0.27, 0.52)
const BEAM := Color(0.9, 0.45, 0.1)
const DECK := Color(0.66, 0.58, 0.44)
const BAY := 2.7
const DEPTH := 1.1
## The first deck is this high; each one after it `LEVEL` above.
const FIRST_LEVEL := 0.15
const LEVEL := 1.4
const POST := 0.08
const BEAM_HEIGHT := 0.12
const DECK_THICK := 0.03
## Frames reach this far above the top deck.
const TOP_CLEAR := 0.6


func title() -> String:
	return "Shelving"


func params() -> Array[Dictionary]:
	return [
		seed_param(),
		param("bays", "Bays", 1.0, 6.0, 1.0, 2.0),
		param("levels", "Levels", 1.0, 5.0, 1.0, 3.0),
		param("fill", "Fill", 0.0, 1.0, 0.05, 0.7),
		voxel_param(0.03, 0.1, 0.04),
	]


static func height(values: Dictionary) -> float:
	var p := VoxShelving.new().with_defaults(values)
	return FIRST_LEVEL + LEVEL * float(int(p["levels"]) - 1) + TOP_CLEAR


## Collision boxes (model space): every upright frame (both posts and the lacing as one slab)
## and every deck across each bay.
static func collision(values: Dictionary) -> Array[AABB]:
	var p := VoxShelving.new().with_defaults(values)
	var bays := int(p["bays"])
	var run := BAY * bays
	var h := height(p)
	var out: Array[AABB] = []
	for i in bays + 1:
		var x := -run / 2.0 + i * BAY
		out.append(AABB(Vector3(x - POST / 2.0, 0.0, -DEPTH / 2.0), Vector3(POST, h, DEPTH)))
	for k in int(p["levels"]):
		var y := FIRST_LEVEL + k * LEVEL
		out.append(AABB(Vector3(-run / 2.0, y - BEAM_HEIGHT, -DEPTH / 2.0), Vector3(run, BEAM_HEIGHT, DEPTH)))
	return out


func build(values: Dictionary) -> VoxelModel:
	var p := with_defaults(values)
	var seed := int(p["seed"])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var bays := int(p["bays"])
	var levels := int(p["levels"])
	var fill: float = p["fill"]
	var v: float = p["voxel"]
	var run := BAY * bays
	var h := height(p)
	var m := new_model()
	m.setup(Vector3(run + POST * 2.0 + v * 4.0, h + v * 4.0, DEPTH + 0.2 + v * 4.0), v)
	m.set_material(VoxMaterials.index_of("sheet_metal"))
	var hz := DEPTH / 2.0
	var lace := maxf(v * 0.6, 0.02)
	for i in bays + 1:
		var x := -run / 2.0 + i * BAY
		for sz: float in [-1.0, 1.0]:
			var z := sz * (hz - POST / 2.0)
			m.fill_box(Vector3(x - POST / 2.0, 0.0, z - POST / 2.0), Vector3(x + POST / 2.0, h, z + POST / 2.0), UPRIGHT, 0.03, seed)
		# Lacing zig-zags up between the frame's two posts.
		var y := 0.3
		var up := true
		while y + 0.6 < h:
			var za := -hz + POST if up else hz - POST
			m.fill_capsule(Vector3(x, y, za), Vector3(x, y + 0.6, -za), lace, lace, UPRIGHT.lightened(0.1), 0.03, seed)
			y += 0.6
			up = not up
		m.fill_box(Vector3(x - POST, 0.0, -hz - 0.03), Vector3(x + POST, maxf(v, 0.02), hz + 0.03), UPRIGHT.darkened(0.2), 0.03, seed)
	for k in levels:
		var y := FIRST_LEVEL + k * LEVEL
		for sz: float in [-1.0, 1.0]:
			var z := sz * hz
			m.fill_box(Vector3(-run / 2.0, y - BEAM_HEIGHT, minf(z, z - sz * 0.06)), Vector3(run / 2.0, y, maxf(z, z - sz * 0.06)), BEAM, 0.03, seed + 1)
		m.set_material(VoxMaterials.index_of("wood"))
		m.fill_box(Vector3(-run / 2.0 + POST / 2.0, y - DECK_THICK, -hz + 0.06), Vector3(run / 2.0 - POST / 2.0, y, hz - 0.06), DECK, 0.06, seed + 2)
		m.set_material(VoxMaterials.index_of("sheet_metal"))
		# Flat packs on this deck, bay by bay: a stack lying along the bay, or a few small ones.
		for b in bays:
			if rng.randf() > fill:
				continue
			var cx := -run / 2.0 + (b + 0.5) * BAY
			var room := LEVEL - BEAM_HEIGHT - 0.15 if k < levels - 1 else TOP_CLEAR - 0.05
			var kind := rng.randi_range(0, VoxFlatPack.BOXES.size() - 1)
			var size: Vector3 = VoxFlatPack.BOXES[kind]
			var stack := clampi(int(room * rng.randf_range(0.4, 1.0) / size.y), 1, 6)
			var across := 2 if size.z < 0.5 else 1
			for row in across:
				var cz := 0.0 if across == 1 else (row - 0.5) * 0.5
				for s in stack:
					var at := Vector3(cx + rng.randf_range(-0.05, 0.05), y + s * size.y, cz + rng.randf_range(-0.03, 0.03))
					VoxFlatPack.draw(m, at, size, rng.randf() < 0.5, seed + 100 + k * 50 + b * 10 + s)
		m.set_material(VoxMaterials.index_of("sheet_metal"))
	return m
