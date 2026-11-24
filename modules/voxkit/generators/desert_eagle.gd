class_name VoxDesertEagle
extends VoxHandgun
## The Desert Eagle, a .50 pistol: a big steel frame running out to the muzzle, a short
## slide at the back with an exposed hammer, a wide grip with a rubber wrap, a squared trigger
## guard with a hook, and the long barrel on top whose sides slope in from a wide flat top
## (triangular from the front), with a rail along the top for a sight. Real-world metres.

const PART_NAMES: Array[String] = ["Whole gun", "Frame and slide", "Barrel", "Magazine"]
const KEYS: Array[String] = ["receiver", "barrel", "magazine"]
const FINISH_NAMES: Array[String] = ["Steel", "Black", "Gold"]
const FINISH_COLOURS := [Color(0.55, 0.56, 0.58), Color(0.13, 0.13, 0.14), Color(0.72, 0.58, 0.25)]
const RUBBER := Color(0.07, 0.07, 0.07)

## The bore's height above the frame's top.
const BORE := 0.02
## The top of the barrel's flat, and of the rail on it.
const BARREL_TOP := 0.034
const RAIL_TOP := 0.038
## The bottom of the rear sight's notch; the front post's top is level with it.
const SIGHT_LINE := 0.044
const REAR_SIGHT_Z := 0.085
const MUZZLE_Z := -0.2
const GRIP_BOTTOM := -0.135
const MOUNTS := {
	"receiver": Vector3.ZERO,
	"barrel": Vector3(0.0, 0.0, -0.045),
	"magazine": Vector3(0.0, GRIP_BOTTOM, 0.068),
}
const GRIP := Vector3(0.0, -0.075, 0.09)
const BOUNDS := {
	"": AABB(Vector3(-0.02, -0.15, -0.21), Vector3(0.04, 0.21, 0.33)),
	"receiver": AABB(Vector3(-0.02, -0.145, -0.21), Vector3(0.04, 0.2, 0.33)),
	"barrel": AABB(Vector3(-0.02, -0.002, -0.21), Vector3(0.04, 0.052, 0.17)),
	"magazine": AABB(Vector3(-0.016, -0.148, 0.025), Vector3(0.032, 0.14, 0.085)),
}


func title() -> String:
	return "Desert Eagle"


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
	return ["magazine", "receiver", "barrel"]


static func part_mesh(part: String) -> ArrayMesh:
	return cut(VoxDesertEagle.new(), part)


func _draw(m: VoxelModel, key: String, finish: int, seed: int) -> void:
	var metal: Color = FINISH_COLOURS[finish]
	match key:
		"receiver":
			_frame(m, metal, seed)
		"barrel":
			_barrel(m, metal, seed)
		"magazine":
			_magazine(m, seed)


## The frame out to under the muzzle with its front corner cut at an angle, the slide behind
## the barrel with serrations, rear sight and hammer, the hooked trigger guard and the
## rubber-wrapped grip.
func _frame(m: VoxelModel, metal: Color, seed: int) -> void:
	var under := metal.darkened(0.12)
	# Narrow under the barrel, so the barrel's sloped sides show from the front.
	_box(m, Vector3(-0.009, -0.022, MUZZLE_Z + 0.006), Vector3(0.009, 0.0, -0.075), under, seed)
	_box(m, Vector3(-0.0155, -0.022, -0.075), Vector3(0.0155, 0.0, 0.06), under, seed)
	# The front of the frame slopes back from the muzzle to the trigger guard.
	var step := m.voxel_size()
	var z := MUZZLE_Z
	while z < -0.15:
		var t := (z - MUZZLE_Z) / 0.05
		_carve(m, Vector3(-0.02, -0.03, z), Vector3(0.02, lerpf(-0.006, -0.022, t), z + step))
		z += step
	_box(m, Vector3(-0.0155, 0.0, -0.045), Vector3(0.0155, 0.03, 0.095), metal, seed)
	_box(m, Vector3(-0.012, 0.03, -0.045), Vector3(0.012, 0.034, 0.093), metal, seed)
	for k in 6:
		var sz := 0.062 + 0.005 * float(k)
		_paint(m, Vector3(-0.017, 0.006, sz), Vector3(0.017, 0.028, sz + 0.0025), metal.darkened(0.4), seed)
	# A dark seam where the slide meets the barrel.
	_paint(m, Vector3(-0.017, 0.0, -0.045), Vector3(0.017, 0.034, -0.042), DARK, seed)
	_rear_sight(m, 0.034, SIGHT_LINE, REAR_SIGHT_Z, 0.011, seed)
	_box(m, Vector3(-0.005, 0.004, 0.095), Vector3(0.005, 0.026, 0.104), DARK, seed)
	_box(m, Vector3(-0.005, 0.02, 0.1), Vector3(0.005, 0.03, 0.11), DARK, seed)
	_box(m, Vector3(-0.017, -0.014, -0.022), Vector3(-0.0155, -0.006, 0.01), DARK, seed)
	# Trigger guard, squared at the front with a hook for the support hand's finger.
	_box(m, Vector3(-0.007, -0.064, -0.066), Vector3(0.007, -0.053, 0.026), under, seed)
	_box(m, Vector3(-0.007, -0.064, -0.074), Vector3(0.007, -0.02, -0.063), under, seed)
	_box(m, Vector3(-0.006, -0.071, -0.075), Vector3(0.006, -0.062, -0.066), under, seed)
	_box(m, Vector3(-0.003, -0.048, -0.026), Vector3(0.003, -0.022, -0.019), DARK, seed)
	_box(m, Vector3(-0.0155, -0.014, 0.06), Vector3(0.0155, 0.0, 0.1), under, seed)
	_grip(m, -0.01, GRIP_BOTTOM, 0.022, 0.04, 0.092, 0.106, 0.0165, RUBBER, seed, 0.004)
	# Finger ridges down the front of the wrap.
	for k in 3:
		var y := -0.05 - 0.022 * float(k)
		var t := (-0.01 - y) / (-0.01 - GRIP_BOTTOM)
		var front := lerpf(0.022, 0.04, t)
		_box(m, Vector3(-0.015, y, front - 0.003), Vector3(0.015, y + 0.008, front + 0.004), RUBBER, seed)


## The barrel: each row narrower than the one above, from the wide flat top down to the
## frame, so it reads triangular from the front; a slotted rail on top, the front post on it
## and the wide bore at the muzzle.
func _barrel(m: VoxelModel, metal: Color, seed: int) -> void:
	var back: float = (MOUNTS["barrel"] as Vector3).z
	var step := m.voxel_size()
	var y := 0.0
	while y < BARREL_TOP:
		var half := lerpf(0.004, 0.0165, y / BARREL_TOP)
		_box(m, Vector3(-half, y, MUZZLE_Z), Vector3(half, y + step, back), metal, seed)
		y += step
	_box(m, Vector3(-0.006, BARREL_TOP, MUZZLE_Z + 0.004), Vector3(0.006, RAIL_TOP, back - 0.004), metal.darkened(0.3), seed)
	for i in 11:
		var z := MUZZLE_Z + 0.016 + 0.012 * float(i)
		_carve(m, Vector3(-0.007, RAIL_TOP - 0.0015, z), Vector3(0.007, RAIL_TOP + 0.001, z + 0.005))
	_box(m, Vector3(-0.0025, RAIL_TOP, MUZZLE_Z + 0.004), Vector3(0.0025, SIGHT_LINE + 0.0005, MUZZLE_Z + 0.012), DARK, seed)
	_bore(m, Vector3(0.0, BORE, MUZZLE_Z), 0.0065)


## The magazine's body inside the grip and its wide baseplate below.
func _magazine(m: VoxelModel, seed: int) -> void:
	_grip(m, -0.012, GRIP_BOTTOM, 0.03, 0.048, 0.082, 0.098, 0.011, DARK, seed)
	_box(m, Vector3(-0.0145, GRIP_BOTTOM - 0.008, 0.038), Vector3(0.0145, GRIP_BOTTOM, 0.108), BLUED, seed)
