class_name VoxFiveSeven
extends VoxHandgun
## The Five-seveN, a 5.7 mm pistol: a slim, long slide over a polymer frame with an
## accessory rail, a squared trigger guard, and a long grip (front to back) that takes the
## long cartridge, with a 20-round magazine or a 30-round one that sticks out below. The slide
## ends in a short threaded stub for a compensator or suppressor. Real-world metres.

const PART_NAMES: Array[String] = ["Whole gun", "Frame", "Slide", "20 round magazine", "30 round magazine"]
const KEYS: Array[String] = ["receiver", "slide", "mag20", "mag30"]
const FINISH_NAMES: Array[String] = ["Black", "Flat dark earth", "Olive"]
const FRAMES := [Color(0.11, 0.11, 0.12), Color(0.52, 0.44, 0.32), Color(0.27, 0.29, 0.2)]
const SLIDE := Color(0.1, 0.1, 0.11)
const MAGAZINE := Color(0.09, 0.09, 0.1)

## Height of the bore above the frame's top (the slide's underside).
const BORE := 0.016
## The bottom of the rear sight's notch; the front post's top is level with it.
const SIGHT_LINE := 0.036
const REAR_SIGHT_Z := 0.064
## The slide's front face, and the threaded stub's end, where a muzzle device goes.
const SLIDE_FRONT := -0.135
const THREAD_END := -0.145
const GRIP_BOTTOM := -0.125
const MOUNTS := {
	"receiver": Vector3.ZERO,
	"slide": Vector3.ZERO,
	"mag20": Vector3(0.0, GRIP_BOTTOM, 0.073),
	"mag30": Vector3(0.0, GRIP_BOTTOM, 0.073),
}
const GRIP := Vector3(0.0, -0.07, 0.077)
const BOUNDS := {
	"": AABB(Vector3(-0.016, -0.135, -0.15), Vector3(0.032, 0.18, 0.265)),
	"receiver": AABB(Vector3(-0.016, -0.13, -0.135), Vector3(0.032, 0.135, 0.25)),
	"slide": AABB(Vector3(-0.014, -0.002, -0.15), Vector3(0.028, 0.045, 0.23)),
	"mag20": AABB(Vector3(-0.014, -0.135, 0.02), Vector3(0.028, 0.13, 0.095)),
	"mag30": AABB(Vector3(-0.014, -0.17, 0.02), Vector3(0.028, 0.165, 0.105)),
}


func title() -> String:
	return "Five-seveN"


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
	return ["mag20", "receiver", "slide"]


static func part_mesh(part: String) -> ArrayMesh:
	return cut(VoxFiveSeven.new(), part)


func _draw(m: VoxelModel, key: String, finish: int, seed: int) -> void:
	var frame: Color = FRAMES[finish]
	match key:
		"receiver":
			_frame(m, frame, seed)
		"slide":
			_slide(m, seed)
		"mag20":
			_magazine(m, false, seed)
		"mag30":
			_magazine(m, true, seed)


## A polymer frame: dust cover with a short rail under it, a big squared trigger guard, and
## the long, slightly raked grip with a beavertail and darker texture bands.
func _frame(m: VoxelModel, colour: Color, seed: int) -> void:
	_box(m, Vector3(-0.012, -0.018, -0.128), Vector3(0.012, 0.0, 0.03), colour, seed)
	_box(m, Vector3(-0.012, -0.009, 0.0), Vector3(0.012, 0.0, 0.085), colour, seed)
	for i in 4:
		var z := -0.122 + 0.014 * float(i)
		_box(m, Vector3(-0.011, -0.023, z), Vector3(0.011, -0.018, z + 0.008), colour.darkened(0.25), seed)
	# Trigger guard: flat bottom, squared front.
	_box(m, Vector3(-0.005, -0.05, -0.058), Vector3(0.005, -0.044, 0.02), colour, seed)
	_box(m, Vector3(-0.005, -0.05, -0.062), Vector3(0.005, -0.018, -0.054), colour, seed)
	_box(m, Vector3(-0.003, -0.04, -0.022), Vector3(0.003, -0.018, -0.016), DARK, seed)
	_grip(m, -0.004, GRIP_BOTTOM, 0.012, 0.042, 0.078, 0.104, 0.0135, colour, seed, 0.004)
	_box(m, Vector3(-0.012, -0.013, 0.078), Vector3(0.012, -0.003, 0.09), colour, seed)
	for k in 5:
		var y := -0.04 - 0.016 * float(k)
		var t := (-0.004 - y) / (-0.004 - GRIP_BOTTOM)
		_paint(m, Vector3(-0.015, y, lerpf(0.012, 0.042, t) + 0.008), Vector3(0.015, y + 0.006, lerpf(0.078, 0.104, t) - 0.008), colour.darkened(0.35), seed)
	_box(m, Vector3(-0.0145, -0.03, 0.014), Vector3(-0.012, -0.024, 0.022), DARK, seed)


## A long, slim slide: front edge bevelled, serrations at the back, the ejection port on the
## right, rear notch and front post, the barrel's crown and a short thread at the front.
func _slide(m: VoxelModel, seed: int) -> void:
	_box(m, Vector3(-0.0115, 0.0, SLIDE_FRONT), Vector3(0.0115, 0.026, 0.074), SLIDE, seed)
	_box(m, Vector3(-0.009, 0.026, SLIDE_FRONT + 0.004), Vector3(0.009, 0.03, 0.072), SLIDE, seed)
	_carve(m, Vector3(-0.02, 0.021, SLIDE_FRONT - 0.002), Vector3(0.02, 0.04, SLIDE_FRONT + 0.005))
	for k in 5:
		var z := 0.042 + 0.006 * float(k)
		_paint(m, Vector3(-0.013, 0.006, z), Vector3(0.013, 0.024, z + 0.003), DARK, seed)
	_paint(m, Vector3(0.009, 0.014, -0.02), Vector3(0.013, 0.026, 0.012), DARK, seed)
	_rear_sight(m, 0.028, SIGHT_LINE, REAR_SIGHT_Z, 0.008, seed)
	_box(m, Vector3(-0.002, 0.028, -0.127), Vector3(0.002, SIGHT_LINE + 0.0005, -0.121), DARK, seed)
	_tube(m, Vector3(0.0, BORE, 0.0), SLIDE_FRONT + 0.002, THREAD_END, 0.0055, DARK, seed)
	_bore(m, Vector3(0.0, BORE, THREAD_END), 0.0035)


## The magazine: its body sits inside the grip (hidden on the gun, shown on its own), with a
## baseplate under the grip; the 30-round one adds a sleeve below.
func _magazine(m: VoxelModel, extended: bool, seed: int) -> void:
	_grip(m, -0.01, GRIP_BOTTOM, 0.022, 0.05, 0.068, 0.096, 0.01, MAGAZINE, seed)
	var bottom := GRIP_BOTTOM
	if extended:
		bottom = -0.158
		_grip(m, GRIP_BOTTOM, bottom, 0.042, 0.05, 0.104, 0.112, 0.0125, MAGAZINE, seed)
	_box(m, Vector3(-0.0125, bottom - 0.006, 0.04 + (0.008 if extended else 0.0)), Vector3(0.0125, bottom, 0.106 + (0.008 if extended else 0.0)), DARK, seed)
