class_name VoxLatticePylon
extends VoxGenerator
## A high-voltage pylon: a galvanised steel lattice (VoxLattice, shared with the radio mast)
## on four concrete feet, tapering from a wide base to a narrow waist, with lattice cross-arms
## reaching out along x and a string of glass insulators hanging from each arm's tip. Double
## circuit: three arms a side, six conductors. Single circuit: a cat-head, the body opening
## out again above the waist to one wide arm with three conductors, the middle one hanging in
## the window. The line runs along z. Centred on its feet, standing on the origin.
## `attach_points` are where the conductors hang (the bottom of each insulator string).

const CIRCUITS: Array[String] = ["Single", "Double"]
const STEEL := Color(0.6, 0.62, 0.62)
const CONCRETE := Color(0.58, 0.57, 0.54)
const GLASS := Color(0.42, 0.55, 0.5)
const ROD := Color(0.3, 0.31, 0.32)
## Each foot's concrete block: metres across and above the ground.
const FOOT := 1.0
const FOOT_HEIGHT := 0.6
## Feet are solid this high for collision; above them the lattice is mostly air.
const FOOT_SOLID := 2.0
const LEG := 0.2
const BRACE := 0.09
## Insulator strings: length, metres between discs, a disc's radius and thickness.
const INSULATOR := 2.4
const DISC_STEP := 0.24
const DISC_RADIUS := 0.17
const DISC_THICK := 0.07
## An arm's depth along the line where it meets the body, and how far its bottom chord drops
## below its top there, metres.
const ARM_DEPTH := 1.6
const ARM_DROP := 1.4
## Double circuit: each arm's height below the top and its reach as a share of `arm`.
const DOUBLE_LEVELS: Array[float] = [2.5, 6.5, 10.0]
const DOUBLE_REACH: Array[float] = [0.7, 1.0, 0.85]
## Single circuit: the arm's height below the top, the waist's below the arm, and the window's
## width at the arm as a share of `arm`.
const SINGLE_ARM := 4.0
const SINGLE_WAIST := 9.0
const SINGLE_WINDOW := 0.8
## The body is this far below the top where the peak starts, metres.
const PEAK := 1.5


func title() -> String:
	return "Lattice pylon"


func params() -> Array[Dictionary]:
	return [
		seed_param(),
		choice("circuits", "Circuits", CIRCUITS, 1),
		param("height", "Height (m)", 25.0, 35.0, 0.5, 30.0),
		param("base", "Base width (m)", 4.0, 7.0, 0.1, 5.5),
		param("waist", "Waist width (m)", 1.4, 2.6, 0.05, 1.8),
		param("arm", "Arm reach (m)", 4.0, 7.0, 0.1, 5.5),
		param("bay", "Bay height (m)", 1.8, 3.5, 0.1, 2.6),
		voxel_param(0.08, 0.2, 0.12),
	]


## Each conductor's arm as [height of the arm's top, x of its tip], left to right, top down.
static func arms(values: Dictionary) -> Array[Vector2]:
	var p := VoxLatticePylon.new().with_defaults(values)
	var h: float = p["height"]
	var arm: float = p["arm"]
	var out: Array[Vector2] = []
	if int(p["circuits"]) == 1:
		for i in DOUBLE_LEVELS.size():
			var y := h - DOUBLE_LEVELS[i]
			out.append(Vector2(y, -arm * DOUBLE_REACH[i]))
			out.append(Vector2(y, arm * DOUBLE_REACH[i]))
	else:
		var y := h - SINGLE_ARM
		out.append(Vector2(y, -arm))
		out.append(Vector2(y, 0.0))
		out.append(Vector2(y, arm))
	return out


## Where the conductors hang (model space): the bottom of each insulator string, three for a
## single circuit, six for a double.
static func attach_points(values: Dictionary) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for a in arms(values):
		out.append(Vector3(a.y, a.x - INSULATOR, 0.0))
	return out


## Collision boxes (model space): the four feet only; wires and arms high up are left to the
## air, as the lattice is.
static func collision(values: Dictionary) -> Array[AABB]:
	var p := VoxLatticePylon.new().with_defaults(values)
	var half := float(p["base"]) / 2.0
	var out: Array[AABB] = []
	for c in VoxLattice.CORNERS:
		out.append(AABB(Vector3(c.x * half - FOOT / 2.0, 0.0, c.y * half - FOOT / 2.0), Vector3(FOOT, FOOT_SOLID, FOOT)))
	return out


func build(values: Dictionary) -> VoxelModel:
	var p := with_defaults(values)
	var seed := int(p["seed"])
	var h: float = p["height"]
	var base: float = p["base"]
	var waist: float = p["waist"]
	var arm: float = p["arm"]
	var bay: float = p["bay"]
	var v: float = p["voxel"]
	var double := int(p["circuits"]) == 1
	var m := new_model()
	var across := maxf(arm * 2.0, base + FOOT) + v * 6.0
	m.setup(Vector3(across, h + v * 4.0, base + FOOT + v * 4.0), v)
	m.set_material(VoxMaterials.index_of("concrete"))
	for c in VoxLattice.CORNERS:
		var at := Vector3(c.x * base / 2.0, 0.0, c.y * base / 2.0)
		m.fill_box(at - Vector3(FOOT / 2.0, 0.0, FOOT / 2.0), at + Vector3(FOOT / 2.0, FOOT_HEIGHT, FOOT / 2.0), CONCRETE, 0.08, seed)
	m.set_material(VoxMaterials.index_of("sheet_metal"))
	var leg_r := maxf(LEG / 2.0, v * 0.75)
	var brace_r := maxf(BRACE / 2.0, v * 0.75)
	var paint := func(_y: float) -> Color: return STEEL
	# The taper: base to waist, then straight (double) or opening out to the window (single).
	var waist_y := h - (DOUBLE_LEVELS[DOUBLE_LEVELS.size() - 1] + ARM_DROP + 1.0) if double else h - SINGLE_ARM - SINGLE_WAIST
	var taper := func(y: float) -> Vector2: return Vector2.ONE * lerpf(base, waist, clampf((y - FOOT_HEIGHT) / (waist_y - FOOT_HEIGHT), 0.0, 1.0))
	VoxLattice.body(m, FOOT_HEIGHT, waist_y, taper, bay, leg_r, brace_r, paint, seed)
	var top_y := h - PEAK
	if double:
		var straight := func(_y: float) -> Vector2: return Vector2.ONE * waist
		VoxLattice.body(m, waist_y, top_y, straight, bay * 0.7, leg_r * 0.8, brace_r, paint, seed)
		_peak(m, Vector2.ONE * waist, top_y, h, brace_r, paint, seed)
		for a in arms(p):
			_arm(m, a.x, waist / 2.0, a.y, brace_r, paint, seed)
	else:
		var arm_y := h - SINGLE_ARM
		var window := arm * SINGLE_WINDOW
		# Opens out across the line only; along it the head keeps the waist's depth.
		var head := func(y: float) -> Vector2: return Vector2(lerpf(waist, window, clampf((y - waist_y) / (arm_y - waist_y), 0.0, 1.0)), waist)
		VoxLattice.body(m, waist_y, arm_y, head, bay * 0.7, leg_r * 0.8, brace_r, paint, seed)
		# The beam across the top of the window and on out to both tips.
		for side: float in [-1.0, 1.0]:
			_arm(m, arm_y, window / 2.0, side * arm, brace_r, paint, seed)
		for z: float in [-waist / 2.0, waist / 2.0]:
			VoxLattice.bar(m, Vector3(-window / 2.0, arm_y, z), Vector3(window / 2.0, arm_y, z), leg_r * 0.8, paint, seed)
		_peak(m, Vector2(window * 0.4, waist), arm_y, h, brace_r, paint, seed)
	for a in arms(p):
		_insulator(m, Vector3(a.y, a.x, 0.0), v, seed)
	return m


## A lattice arm from the body's face (`from` metres out from the middle) to its tip at `tip`
## (x, signed), its top level at `y`: two top chords closing to the tip, a bottom chord rising
## to it, and diagonals between.
func _arm(m: VoxelModel, y: float, from: float, tip: float, r: float, paint: Callable, seed: int) -> void:
	var side := signf(tip) if tip != 0.0 else 1.0
	var start := side * from
	if absf(tip) <= from:
		return
	var tip_at := Vector3(tip, y, 0.0)
	var bottom := Vector3(start, y - ARM_DROP, 0.0)
	for z: float in [-ARM_DEPTH / 2.0, ARM_DEPTH / 2.0]:
		var root := Vector3(start, y, z)
		VoxLattice.bar(m, root, tip_at + Vector3(0.0, 0.0, z * 0.15), r * 1.2, paint, seed)
		VoxLattice.bar(m, root, bottom, r, paint, seed)
	VoxLattice.bar(m, bottom, tip_at, r * 1.2, paint, seed)
	var panels := maxi(ceili(absf(tip - start) / 1.2), 1)
	for k in panels:
		var t0 := float(k) / panels
		var t1 := float(k + 1) / panels
		var low := bottom.lerp(tip_at, t1)
		for z: float in [-ARM_DEPTH / 2.0, ARM_DEPTH / 2.0]:
			var top := Vector3(lerpf(start, tip, t0), y, z * lerpf(1.0, 0.15, t0))
			VoxLattice.bar(m, top, low, r, paint, seed)


## The peak over the body: its corners drawn in to a point at `h`.
func _peak(m: VoxelModel, size: Vector2, y: float, h: float, r: float, paint: Callable, seed: int) -> void:
	for c in VoxLattice.CORNERS:
		VoxLattice.bar(m, Vector3(c.x * size.x / 2.0, y, c.y * size.y / 2.0), Vector3(0.0, h - r, 0.0), r, paint, seed)


## A string of glass discs on a dark rod hanging from `at`.
func _insulator(m: VoxelModel, at: Vector3, v: float, seed: int) -> void:
	m.set_material(VoxMaterials.index_of("sheet_metal"))
	m.fill_box(at + Vector3(-v * 0.6, -INSULATOR, -v * 0.6), at + Vector3(v * 0.6, 0.0, v * 0.6), ROD, 0.0, seed)
	var y := at.y - DISC_STEP
	while y > at.y - INSULATOR + DISC_STEP * 0.5:
		m.fill_cylinder(Vector3(at.x, y, at.z), maxf(DISC_RADIUS, v * 1.5), maxf(DISC_THICK, v), GLASS, 0.03, seed)
		y -= DISC_STEP
