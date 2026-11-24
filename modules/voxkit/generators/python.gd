class_name VoxPython
extends VoxHandgun
## The Python, a .357 revolver with a 6-inch barrel: a frame with a top strap over a fluted
## six-shot cylinder, the hammer behind it and a round trigger guard; a barrel with a
## ventilated rib along the top and a full-length lug underneath, a ramp front sight; and a
## checkered wooden grip. Real-world metres.

const PART_NAMES: Array[String] = ["Whole gun", "Frame and cylinder", "Barrel", "Grip"]
const KEYS: Array[String] = ["receiver", "barrel", "grip"]
const FINISH_NAMES: Array[String] = ["Blued", "Stainless"]
const FINISH_COLOURS := [Color(0.12, 0.14, 0.2), Color(0.6, 0.61, 0.63)]
const WOOD := Color(0.42, 0.24, 0.12)
const SIGHT_INSERT := Color(0.78, 0.14, 0.1)
const MEDALLION := Color(0.75, 0.6, 0.25)

## The bore is at y 0; the cylinder turns below it, its top chamber in line with the bore.
const CYLINDER_AXIS := Vector3(0.0, -0.013, 0.0)
const CYLINDER_RADIUS := 0.021
const CYLINDER_FRONT := -0.024
const CYLINDER_BACK := 0.018
const CHAMBERS := 6
const BARREL_RADIUS := 0.0095
## The vent rib's top, and the bottom of the rear sight's notch (the front ramp's top is
## level with it).
const RIB_TOP := 0.0185
const SIGHT_LINE := 0.026
const REAR_SIGHT_Z := 0.04
## Six inches of barrel in front of the frame.
const BARREL_LENGTH := 0.152
const MOUNTS := {
	"receiver": Vector3.ZERO,
	"barrel": Vector3(0.0, 0.0, -0.034),
	"grip": Vector3(0.0, -0.03, 0.05),
}
const GRIP := Vector3(0.0, -0.075, 0.072)
const BOUNDS := {
	"": AABB(Vector3(-0.018, -0.14, -0.195), Vector3(0.036, 0.175, 0.305)),
	"receiver": AABB(Vector3(-0.018, -0.07, -0.04), Vector3(0.036, 0.105, 0.11)),
	"barrel": AABB(Vector3(-0.012, -0.032, -0.195), Vector3(0.024, 0.062, 0.165)),
	"grip": AABB(Vector3(-0.017, -0.14, 0.02), Vector3(0.034, 0.115, 0.09)),
}


func title() -> String:
	return "Python revolver"


func parts() -> Array[String]:
	return PART_NAMES


func part_keys() -> Array[String]:
	return KEYS


func mounts() -> Dictionary:
	return MOUNTS


func bounds() -> Dictionary:
	return BOUNDS


func finishes() -> Array[String]:
	return FINISH_NAMES


func draw_order() -> Array[String]:
	return ["grip", "receiver", "barrel"]


static func part_mesh(part: String) -> ArrayMesh:
	return cut(VoxPython.new(), part)


func _draw(m: VoxelModel, key: String, finish: int, seed: int) -> void:
	var metal: Color = FINISH_COLOURS[finish]
	match key:
		"receiver":
			_frame(m, metal, seed)
		"barrel":
			_barrel(m, metal, seed)
		"grip":
			_wood_grip(m, seed)


## The frame: a ring round the barrel's end, the top strap with the rear sight, the strap
## under the cylinder, the recoil shield behind it, the hammer, the cylinder latch on the
## left and a round trigger guard. Then the cylinder: six flutes between the chambers and
## the chamber mouths dark on its front face.
func _frame(m: VoxelModel, metal: Color, seed: int) -> void:
	_box(m, Vector3(-0.0105, -0.012, -0.034), Vector3(0.0105, 0.0105, CYLINDER_FRONT - 0.001), metal, seed)
	_box(m, Vector3(-0.009, 0.0075, -0.034), Vector3(0.009, 0.017, 0.048), metal, seed)
	_box(m, Vector3(-0.009, -0.04, -0.03), Vector3(0.009, -0.033, 0.035), metal, seed)
	_box(m, Vector3(-0.0115, -0.04, CYLINDER_BACK + 0.001), Vector3(0.0115, 0.017, 0.032), metal, seed)
	_box(m, Vector3(-0.009, -0.032, 0.032), Vector3(0.009, 0.014, 0.06), metal, seed)
	_rear_sight(m, 0.017, SIGHT_LINE, REAR_SIGHT_Z, 0.007, seed)
	# Hammer: a body behind the top strap and a checkered spur back over the hand.
	_box(m, Vector3(-0.004, -0.002, 0.048), Vector3(0.004, 0.022, 0.056), DARK, seed)
	_box(m, Vector3(-0.0045, 0.016, 0.052), Vector3(0.0045, 0.025, 0.066), DARK, seed)
	_box(m, Vector3(-0.0125, -0.002, 0.034), Vector3(-0.009, 0.006, 0.046), DARK, seed)
	var guard := [Vector3(0.0, -0.038, -0.014), Vector3(0.0, -0.06, -0.004), Vector3(0.0, -0.064, 0.016), Vector3(0.0, -0.052, 0.036), Vector3(0.0, -0.036, 0.042)]
	for i in guard.size() - 1:
		_rod(m, guard[i], guard[i + 1], 0.0042, metal, seed)
	_rod(m, Vector3(0.0, -0.038, 0.008), Vector3(0.0, -0.054, 0.016), 0.0025, DARK, seed)
	_cylinder(m, metal, seed)


func _cylinder(m: VoxelModel, metal: Color, seed: int) -> void:
	var a := CYLINDER_AXIS
	# A shade off the frame, with dark gaps front and back, so the cylinder reads as its own
	# round part.
	_tube(m, a, CYLINDER_BACK, CYLINDER_FRONT, CYLINDER_RADIUS, metal.lightened(0.18), seed)
	var r := CYLINDER_RADIUS + 0.002
	for z: float in [CYLINDER_FRONT - 0.002, CYLINDER_BACK]:
		_carve(m, Vector3(-r, -0.032, z), Vector3(r, 0.0075, z + 0.002))
	var chamber_r := -a.y
	for k in CHAMBERS:
		# The top chamber is in line with the bore; flutes run between neighbours.
		var chamber := PI / 2.0 + TAU * float(k) / float(CHAMBERS)
		var flute := chamber + PI / float(CHAMBERS)
		var f := a + Vector3(cos(flute), sin(flute), 0.0) * (CYLINDER_RADIUS + 0.002)
		var flute_front := _g(Vector3(f.x, f.y, CYLINDER_FRONT + 0.012))
		var flute_back := _g(Vector3(f.x, f.y, CYLINDER_BACK - 0.012))
		# Shaded flutes, so the cylinder reads round from the side as well as end on.
		m.carve_capsule(flute_front, flute_back, 0.0045, 0.0045)
		var shade := Vector3(cos(flute), sin(flute), 0.0) * 0.002
		m.paint_box(flute_front + shade - Vector3(0.006, 0.006, 0.0), flute_back + shade + Vector3(0.006, 0.006, 0.0), metal.darkened(0.45), 0.0, seed)
		var c := a + Vector3(cos(chamber), sin(chamber), 0.0) * chamber_r
		m.paint_ellipsoid(_g(Vector3(c.x, c.y, CYLINDER_FRONT)), Vector3(0.0038, 0.0038, 0.003), DARK, 0.0, seed)


## The barrel: the tube, a full-length lug under it with a rounded bottom and the ejector
## rod's end, a rib on posts along the top with windows between them, the ramp front sight
## with a red insert, and the bore.
func _barrel(m: VoxelModel, metal: Color, seed: int) -> void:
	var back: float = (MOUNTS["barrel"] as Vector3).z
	var front := back - BARREL_LENGTH
	_tube(m, Vector3.ZERO, back, front, BARREL_RADIUS, metal, seed)
	_box(m, Vector3(-0.0065, -0.017, front), Vector3(0.0065, -0.004, back), metal, seed)
	_rod(m, Vector3(0.0, -0.017, front + 0.0065), Vector3(0.0, -0.017, back - 0.0065), 0.0065, metal, seed)
	m.paint_ellipsoid(_g(Vector3(0.0, -0.015, front)), Vector3(0.003, 0.003, 0.002), DARK, 0.0, seed)
	_box(m, Vector3(-0.0035, BARREL_RADIUS - 0.002, front), Vector3(0.0035, RIB_TOP, back), metal, seed)
	_box(m, Vector3(-0.0055, RIB_TOP - 0.004, front), Vector3(0.0055, RIB_TOP, back), metal, seed)
	for i in 6:
		var z := back - 0.018 - 0.023 * float(i)
		_carve(m, Vector3(-0.007, BARREL_RADIUS, z - 0.009), Vector3(0.007, RIB_TOP - 0.004, z + 0.009))
	_box(m, Vector3(-0.0015, RIB_TOP, front + 0.004), Vector3(0.0015, SIGHT_LINE + 0.0005, front + 0.016), DARK, seed)
	_paint(m, Vector3(-0.002, RIB_TOP + 0.003, front + 0.013), Vector3(0.002, SIGHT_LINE + 0.001, front + 0.017), SIGHT_INSERT, seed)
	_bore(m, Vector3(0.0, 0.0, front), 0.0045)


## A walnut grip, raked back with a rounded butt, checkered panels on both sides and a small
## medallion near the top.
func _wood_grip(m: VoxelModel, seed: int) -> void:
	var top := -0.028
	var bottom := -0.13
	_grip(m, top, bottom, 0.03, 0.042, 0.064, 0.088, 0.0145, WOOD, seed, 0.009)
	var cell := 0.005
	var rows := int((0.07) / cell)
	for r in rows:
		var y := -0.04 - cell * float(r)
		var t := (top - y) / (top - bottom)
		var lo := lerpf(0.03, 0.042, t) + 0.007
		var hi := lerpf(0.064, 0.088, t) - 0.007
		var z := lo + cell * float(r % 2)
		while z < hi:
			_paint(m, Vector3(-0.016, y, z), Vector3(0.016, y + cell, minf(z + cell, hi)), WOOD.darkened(0.3), seed)
			z += cell * 2.0
	for side: float in [-1.0, 1.0]:
		_paint(m, Vector3(side * 0.0145 - 0.004, -0.042, 0.05), Vector3(side * 0.0145 + 0.004, -0.034, 0.058), MEDALLION, seed)
