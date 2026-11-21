class_name VoxPowerPole
extends VoxGenerator
## A wooden power pole: a round weathered pole, a timber crossarm across the line (along x)
## near the top with two slanting braces under it, and white porcelain pin insulators on the
## arm, two or three of them (the third on top of the pole). The line runs along z. Stands on
## the origin. `attach_points` are where the conductors sit (the top of each insulator).
## A pole where another line branches off has a second crossarm a little lower, turned `tap`
## degrees round the pole (the branch's line runs along its own z), clamped to the pole's
## side; `tap_points` are its conductors, all on the arm.

const WIRES: Array[String] = ["Two", "Three"]
const POLE := Color(0.42, 0.36, 0.3)
const ARM := Color(0.47, 0.41, 0.33)
const PORCELAIN := Color(0.88, 0.88, 0.85)
const BRACE := Color(0.32, 0.32, 0.33)
## The crossarm: metres below the top, and its section (up, along the line).
const ARM_BELOW := 0.45
const ARM_SECTION := Vector2(0.12, 0.1)
## Insulators: radius and height, and how far in from the arm's ends they sit, metres.
const PIN_RADIUS := 0.07
const PIN_HEIGHT := 0.22
const PIN_INSET := 0.15
## How far below the crossarm its braces meet the pole, metres.
const BRACE_DROP := 0.7
## How far below the crossarm a branch's arm is: its wires pass under the line's own.
const TAP_DROP := 1.0


func title() -> String:
	return "Power pole"


func params() -> Array[Dictionary]:
	return [
		seed_param(),
		choice("wires", "Wires", WIRES, 1),
		param("height", "Height (m)", 8.0, 10.0, 0.1, 9.0),
		param("radius", "Pole radius (m)", 0.1, 0.18, 0.01, 0.13),
		param("arm", "Crossarm length (m)", 1.4, 2.6, 0.05, 2.0),
		param("tap", "Branch arm (degrees round, -1 none)", -1.0, 355.0, 5.0, -1.0),
		voxel_param(0.04, 0.1, 0.05),
	]


## Where the conductors sit (model space): the top of each insulator, left to right, the top
## one last.
static func attach_points(values: Dictionary) -> Array[Vector3]:
	var p := VoxPowerPole.new().with_defaults(values)
	var h: float = p["height"]
	var half := float(p["arm"]) / 2.0 - PIN_INSET
	var arm_top := h - ARM_BELOW + ARM_SECTION.x / 2.0
	var out: Array[Vector3] = [Vector3(-half, arm_top + PIN_HEIGHT, 0.0), Vector3(half, arm_top + PIN_HEIGHT, 0.0)]
	if int(p["wires"]) == 1:
		out.append(Vector3(0.0, h + PIN_HEIGHT, 0.0))
	return out


## Where a branch's conductors sit (model space) on its arm, left to right as seen along the
## branch; empty without one. As many as the pole's own.
static func tap_points(values: Dictionary) -> Array[Vector3]:
	var p := VoxPowerPole.new().with_defaults(values)
	var out: Array[Vector3] = []
	if float(p["tap"]) < 0.0:
		return out
	var turn := Basis(Vector3.UP, deg_to_rad(float(p["tap"])))
	var half := float(p["arm"]) / 2.0 - PIN_INSET
	var y := float(p["height"]) - ARM_BELOW - TAP_DROP + ARM_SECTION.x / 2.0 + PIN_HEIGHT
	# Clear of the pole, so a middle insulator does not stand in it.
	var off := float(p["radius"]) + ARM_SECTION.y
	var xs: Array[float] = [-half, half]
	if int(p["wires"]) == 1:
		xs.insert(1, 0.0)
	for x in xs:
		out.append(turn * Vector3(x, y, off))
	return out


## Collision boxes (model space): the pole only.
static func collision(values: Dictionary) -> Array[AABB]:
	var p := VoxPowerPole.new().with_defaults(values)
	var r: float = p["radius"]
	return [AABB(Vector3(-r, 0.0, -r), Vector3(r * 2.0, float(p["height"]), r * 2.0))]


func build(values: Dictionary) -> VoxelModel:
	var p := with_defaults(values)
	var seed := int(p["seed"])
	var h: float = p["height"]
	var r: float = p["radius"]
	var arm: float = p["arm"]
	var v: float = p["voxel"]
	var tapped := float(p["tap"]) >= 0.0
	var m := new_model()
	var deep := arm + r * 2.0 if tapped else maxf(r * 2.0, ARM_SECTION.y)
	m.setup(Vector3(arm + r * 2.0 + v * 4.0, h + PIN_HEIGHT + v * 4.0, deep + v * 4.0), v)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	m.set_material(VoxMaterials.index_of("wood"))
	# Thicker at the foot, as a trunk is.
	m.fill_capsule(Vector3(0.0, 0.0, 0.0), Vector3(0.0, h - r * 0.5, 0.0), r * 1.15, r * 0.85, POLE.lightened(rng.randf_range(-0.06, 0.08)), 0.12, seed)
	var arm_y := h - ARM_BELOW
	var lo := Vector3(-arm / 2.0, arm_y - ARM_SECTION.x / 2.0, -ARM_SECTION.y / 2.0)
	m.fill_box(lo, lo + Vector3(arm, ARM_SECTION.x, ARM_SECTION.y), ARM, 0.1, seed + 1)
	m.set_material(VoxMaterials.index_of("sheet_metal"))
	var brace_r := maxf(0.025, v * 0.6)
	for side: float in [-1.0, 1.0]:
		m.fill_capsule(Vector3(0.0, arm_y - BRACE_DROP, 0.0), Vector3(side * arm * 0.3, arm_y - ARM_SECTION.x / 2.0, 0.0), brace_r, brace_r, BRACE, 0.03, seed)
	var taps := tap_points(p)
	if tapped:
		m.set_material(VoxMaterials.index_of("wood"))
		var turn := Basis(Vector3.UP, deg_to_rad(float(p["tap"])))
		var y := arm_y - TAP_DROP
		var off := r + ARM_SECTION.y
		var beam_r := ARM_SECTION.x / 2.0
		m.fill_capsule(turn * Vector3(-arm / 2.0, y, off), turn * Vector3(arm / 2.0, y, off), beam_r, beam_r, ARM, 0.1, seed + 2)
		# A bracket back to the pole.
		m.fill_capsule(Vector3(0.0, y, 0.0), turn * Vector3(0.0, y, off), beam_r, beam_r, ARM, 0.1, seed + 2)
	m.set_material(VoxMaterials.index_of("default"))
	for at in attach_points(p) + taps:
		m.fill_cylinder(at - Vector3(0.0, PIN_HEIGHT, 0.0), maxf(PIN_RADIUS, v * 1.2), PIN_HEIGHT, PORCELAIN, 0.02, seed)
	return m
