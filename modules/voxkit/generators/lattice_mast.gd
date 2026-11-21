class_name VoxLatticeMast
extends VoxGenerator
## A radio mast: a square lattice of thin steel members on a concrete footing, four corner
## legs tapering upward with a ring and crossed diagonals at every bay, a whip on top and
## dishes and panel antennas clamped near the top. Galvanised grey or painted in red and white
## bands. Centred on its footing, standing on the origin.

const PAINTS: Array[String] = ["Galvanised", "Red and white"]
const STEEL := Color(0.52, 0.54, 0.55)
const RED := Color(0.66, 0.16, 0.12)
const WHITE := Color(0.86, 0.85, 0.82)
const CONCRETE := Color(0.58, 0.57, 0.54)
## Dark against the sky, so they read from the ground.
const DISH := Color(0.27, 0.28, 0.3)
const PANEL := Color(0.3, 0.31, 0.33)
const DISH_FACE := Color(0.84, 0.84, 0.82)
## Half a dish's thickness, metres.
const DISH_DEPTH := 0.22
## Half a panel antenna (across, up, thick), metres.
const PANEL_SIZE := Vector3(0.35, 0.95, 0.08)
const FOOTING := 0.35
## The footing reaches this far past the legs, metres.
const FOOTING_MARGIN := 0.4
const LEG := 0.14
const BRACE := 0.08
const WHIP := 2.5
## Painted bands are this tall, metres.
const BAND := 3.0
## The bottom of the mast up to this height is one solid box for collision; above it the
## lattice is mostly air, so only a thin box up the middle stops bodies and rounds.
const SOLID_BASE := 2.5


func title() -> String:
	return "Lattice mast"


func params() -> Array[Dictionary]:
	return [
		seed_param(),
		choice("paint", "Paint", PAINTS, 0),
		param("height", "Height (m)", 15.0, 25.0, 0.5, 20.0),
		param("base", "Base width (m)", 1.6, 3.0, 0.1, 2.4),
		param("top", "Top width (m)", 0.5, 1.2, 0.05, 0.7),
		param("bay", "Bay height (m)", 1.0, 2.5, 0.1, 1.6),
		param("dishes", "Dishes", 0.0, 4.0, 1.0, 2.0),
		param("panels", "Panels", 0.0, 4.0, 1.0, 3.0),
		voxel_param(0.06, 0.15, 0.1),
	]


## Half the lattice's width at `y` up a mast `h` tall.
static func half_width(base: float, top: float, h: float, y: float) -> float:
	return lerpf(base, top, clampf(y / h, 0.0, 1.0)) / 2.0


## Collision boxes (model space) for these values: the footing and the bottom of the
## lattice as one box, then a thin one up the middle to the top.
static func collision(values: Dictionary) -> Array[AABB]:
	var p := VoxLatticeMast.new().with_defaults(values)
	var h: float = p["height"]
	var base: float = p["base"]
	var top: float = p["top"]
	var foot := base + FOOTING_MARGIN * 2.0
	var out: Array[AABB] = []
	out.append(AABB(Vector3(-foot / 2.0, 0.0, -foot / 2.0), Vector3(foot, FOOTING, foot)))
	out.append(AABB(Vector3(-base / 2.0, 0.0, -base / 2.0), Vector3(base, SOLID_BASE, base)))
	out.append(AABB(Vector3(-top / 2.0, 0.0, -top / 2.0), Vector3(top, h, top)))
	return out


func build(values: Dictionary) -> VoxelModel:
	var p := with_defaults(values)
	var seed := int(p["seed"])
	var h: float = p["height"]
	var base: float = p["base"]
	var top: float = p["top"]
	var bay: float = p["bay"]
	var v: float = p["voxel"]
	var banded := int(p["paint"]) == 1
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var m := new_model()
	var reach := maxf(base + FOOTING_MARGIN * 2.0, top + 3.4)
	m.setup(Vector3(reach + v * 4.0, h + WHIP + v * 4.0, reach + v * 4.0), v)
	m.set_material(VoxMaterials.index_of("concrete"))
	var foot := base / 2.0 + FOOTING_MARGIN
	m.fill_box(Vector3(-foot, 0.0, -foot), Vector3(foot, FOOTING, foot), CONCRETE, 0.08, seed)
	m.set_material(VoxMaterials.index_of("sheet_metal"))
	var corners: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	# Members are drawn in short pieces so each takes the band colour at its height.
	var leg_r := maxf(LEG / 2.0, v * 0.75)
	var brace_r := maxf(BRACE / 2.0, v * 0.75)
	for c in corners:
		_bar(m, _at(c, base, top, h, FOOTING), _at(c, base, top, h, h), leg_r, banded, seed)
	var y := FOOTING
	while y < h - 0.01:
		var y1 := minf(y + bay, h)
		for k in 4:
			var a := corners[k]
			var b := corners[(k + 1) % 4]
			_bar(m, _at(a, base, top, h, y1), _at(b, base, top, h, y1), brace_r, banded, seed)
			# Crossed diagonals on each face of the bay.
			_bar(m, _at(a, base, top, h, y), _at(b, base, top, h, y1), brace_r, banded, seed)
			_bar(m, _at(b, base, top, h, y), _at(a, base, top, h, y1), brace_r, banded, seed)
		y = y1
	# The whip: a thin pole above the top.
	m.fill_box(Vector3(-v * 0.5, h, -v * 0.5), Vector3(v * 0.5, h + WHIP, v * 0.5), STEEL.darkened(0.2), 0.02, seed)
	# Dishes round the top, each looking out from its own face (opposite faces first), the
	# next a bay lower: a dark shell with a pale round face and a feed at its middle.
	var faces: Array[Vector3] = [Vector3.RIGHT, Vector3.BACK, Vector3.LEFT, Vector3.FORWARD]
	var first := rng.randi_range(0, 3)
	var dish_faces: Array[int] = [0, 2, 1, 3]
	for i in int(p["dishes"]):
		var face := faces[(first + dish_faces[i % 4]) % 4]
		var dy := h - 1.2 - float(i % 2) * 2.2 - rng.randf_range(0.0, 0.3)
		var r := rng.randf_range(0.75, 0.95)
		var out := half_width(base, top, h, dy) + 0.35
		var centre := face * out + Vector3.UP * dy
		var radii := Vector3(r, r, r)
		var lip := Vector3(r, r, r)
		if absf(face.x) > 0.5:
			radii.x = DISH_DEPTH
			lip.x = 0.0
		else:
			radii.z = DISH_DEPTH
			lip.z = 0.0
		m.fill_ellipsoid(centre, radii, DISH, 0.02, seed + 20 + i)
		# The face: everything of the dish on the outward side of its middle.
		var outer := centre + face * DISH_DEPTH * 0.5
		m.paint_box(outer - lip - face.abs() * DISH_DEPTH * 0.5, outer + lip + face.abs() * DISH_DEPTH * 0.5, DISH_FACE, 0.02, seed + 30 + i)
		_bar(m, centre, centre + face * (DISH_DEPTH + 0.35), v * 0.75, false, seed)
		_bar(m, face * (out - 0.35) + Vector3.UP * dy, centre, v * 0.75, false, seed)
	# Flat panel antennas, upright, one to a face below the dishes.
	for i in int(p["panels"]):
		var face := faces[(first + 1 + i) % 4]
		var dy := h - 5.6
		var at := face * (half_width(base, top, h, dy) + 0.2) + Vector3.UP * dy
		var half := Vector3(PANEL_SIZE.z, PANEL_SIZE.y, PANEL_SIZE.x) if absf(face.x) > 0.5 else PANEL_SIZE
		m.fill_box(at - half, at + half, PANEL, 0.0, seed + 40 + i)
	return m


static func _at(corner: Vector2, base: float, top: float, h: float, y: float) -> Vector3:
	var half := half_width(base, top, h, y)
	return Vector3(corner.x * half, y, corner.y * half)


## A straight member from `a` to `b`, in pieces short enough to follow the bands.
func _bar(m: VoxelModel, a: Vector3, b: Vector3, r: float, banded: bool, seed: int) -> void:
	var pieces := maxi(ceili(a.distance_to(b) / 0.5), 1)
	for k in pieces:
		var p0 := a.lerp(b, float(k) / pieces)
		var p1 := a.lerp(b, float(k + 1) / pieces)
		var colour := STEEL
		if banded:
			colour = RED if int(floorf((p0.y + p1.y) * 0.5 / BAND)) % 2 == 0 else WHITE
		m.fill_capsule(p0, p1, r, r, colour, 0.04, seed)
