class_name VoxTerminalGantry
extends VoxGenerator
## A substation's terminal gantry, where a high-voltage line comes down into the yard: two
## steel lattice posts (VoxLattice) either side with lattice beams between them, and a short
## insulator under the beam for each conductor. Its conductors sit across x as a lattice
## pylon's with the same `circuits` and `arm` do (VoxLatticePylon.arms), at the same sides
## and in the same order, so wires run straight from one to the other. The line runs along z.
## Stands on the origin.

const STEEL := VoxLatticePylon.STEEL
const CONCRETE := VoxLatticePylon.CONCRETE
const POST := 0.9
const LEG := 0.14
const BRACE := 0.07
## Each post stands this far outside the furthest conductor, metres.
const POST_OUT := 0.9
## A double circuit's beams: this far apart, top down, metres.
const LEVEL_STEP := 2.5
const INSULATOR := 1.0
const FOOT_HEIGHT := 0.4


func title() -> String:
	return "Terminal gantry"


func params() -> Array[Dictionary]:
	return [
		seed_param(),
		choice("circuits", "Circuits", VoxLatticePylon.CIRCUITS, 1),
		param("height", "Height (m)", 16.0, 30.0, 0.5, 26.0),
		param("arm", "Arm reach (m)", 4.0, 7.0, 0.1, 5.5),
		voxel_param(0.08, 0.2, 0.12),
	]


## Each conductor's beam height and x, as VoxLatticePylon.arms gives them (Vector2(y, x)).
static func arms(values: Dictionary) -> Array[Vector2]:
	var p := VoxTerminalGantry.new().with_defaults(values)
	var h: float = p["height"]
	var out: Array[Vector2] = []
	var pylon := VoxLatticePylon.arms({"circuits": p["circuits"], "arm": p["arm"], "height": 30.0})
	# The pylon's levels, top down, become the gantry's beams, top down.
	var levels: Array[float] = []
	for a in pylon:
		if not levels.has(a.x):
			levels.append(a.x)
	levels.sort()
	levels.reverse()
	for a in pylon:
		out.append(Vector2(h - LEVEL_STEP * levels.find(a.x), a.y))
	return out


static func attach_points(values: Dictionary) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for a in arms(values):
		out.append(Vector3(a.y, a.x - INSULATOR, 0.0))
	return out


static func _half(values: Dictionary) -> float:
	var reach := 0.0
	for a in arms(values):
		reach = maxf(reach, absf(a.y))
	return reach + POST_OUT


## Collision boxes (model space): the two posts' feet.
static func collision(values: Dictionary) -> Array[AABB]:
	var x := _half(values)
	var out: Array[AABB] = []
	for side: float in [-1.0, 1.0]:
		out.append(AABB(Vector3(side * x - POST / 2.0, 0.0, -POST / 2.0), Vector3(POST, 2.0, POST)))
	return out


func build(values: Dictionary) -> VoxelModel:
	var p := with_defaults(values)
	var seed := int(p["seed"])
	var h: float = p["height"]
	var v: float = p["voxel"]
	var x := _half(p)
	var m := new_model()
	m.setup(Vector3(x * 2.0 + POST + v * 4.0, h + v * 4.0, POST + v * 4.0), v)
	m.set_material(VoxMaterials.index_of("concrete"))
	for side: float in [-1.0, 1.0]:
		m.fill_box(Vector3(side * x - POST * 0.7, 0.0, -POST * 0.7), Vector3(side * x + POST * 0.7, FOOT_HEIGHT, POST * 0.7), CONCRETE, 0.08, seed)
	m.set_material(VoxMaterials.index_of("sheet_metal"))
	var paint := func(_y: float) -> Color: return STEEL
	var leg_r := maxf(LEG / 2.0, v * 0.75)
	var brace_r := maxf(BRACE / 2.0, v * 0.75)
	var size := func(_y: float) -> Vector2: return Vector2.ONE * POST
	for side: float in [-1.0, 1.0]:
		VoxLattice.body(m, FOOT_HEIGHT, h, size, 1.5, leg_r, brace_r, paint, seed, Vector3(side * x, 0.0, 0.0))
	var levels: Array[float] = []
	for a in arms(p):
		if not levels.has(a.x):
			levels.append(a.x)
	for y in levels:
		for z: float in [-POST / 2.0, POST / 2.0]:
			VoxLattice.bar(m, Vector3(-x, y, z), Vector3(x, y, z), leg_r, paint, seed)
		# Zigzag between the beam's two chords, seen from below.
		var panels := maxi(ceili(x * 2.0 / 1.2), 1)
		for k in panels:
			var x0 := lerpf(-x, x, float(k) / panels)
			var x1 := lerpf(-x, x, float(k + 1) / panels)
			VoxLattice.bar(m, Vector3(x0, y, -POST / 2.0), Vector3(x1, y, POST / 2.0), brace_r, paint, seed)
	for a in arms(p):
		m.fill_box(Vector3(a.y - v * 0.6, a.x - INSULATOR, -v * 0.6), Vector3(a.y + v * 0.6, a.x, v * 0.6), VoxLatticePylon.ROD, 0.0, seed)
		var y := a.x - VoxLatticePylon.DISC_STEP
		while y > a.x - INSULATOR + VoxLatticePylon.DISC_STEP * 0.5:
			m.fill_cylinder(Vector3(a.y, y, 0.0), maxf(VoxLatticePylon.DISC_RADIUS, v * 1.5), maxf(VoxLatticePylon.DISC_THICK, v), VoxLatticePylon.GLASS, 0.03, seed)
			y -= VoxLatticePylon.DISC_STEP
	return m

