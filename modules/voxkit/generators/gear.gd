class_name VoxGear
extends VoxGenerator
## Carried gear as small voxel models, for inventory icons and items lying on the ground: a
## field medkit, a chest rig, a backpack (day pack or raid pack) and a data drive. Sizes are
## real-world metres.

const KINDS: Array[String] = ["Medkit", "Chest rig", "Assault rig", "Day pack", "Raid pack", "Drive"]
const OLIVE := Color(0.33, 0.37, 0.25)
const KHAKI := Color(0.5, 0.45, 0.32)
const STRAP := Color(0.18, 0.19, 0.15)
const BUCKLE := Color(0.12, 0.12, 0.12)
const RED := Color(0.66, 0.16, 0.13)
const WHITE := Color(0.9, 0.89, 0.85)
const METAL := Color(0.62, 0.63, 0.66)
const CASE := Color(0.14, 0.15, 0.17)
const LED := Color(0.95, 0.65, 0.15)


func title() -> String:
	return "Gear"


func params() -> Array[Dictionary]:
	return [
		seed_param(),
		choice("kind", "Kind", KINDS, 0),
		voxel_param(0.005, 0.03, 0.01),
	]


## The kind index for an item's `model` name (medkit, rig_light, rig_heavy, bag_small,
## bag_large, drive), or -1.
static func kind_of(model: String) -> int:
	return ["medkit", "rig_light", "rig_heavy", "bag_small", "bag_large", "drive"].find(model)


func build(values: Dictionary) -> VoxelModel:
	var p := with_defaults(values)
	var seed := int(p["seed"])
	var v: float = p["voxel"]
	var m := new_model()
	match int(p["kind"]):
		0:
			_medkit(m, v, seed)
		1:
			_rig(m, v, seed, 3)
		2:
			_rig(m, v, seed, 5)
		3:
			_pack(m, v, seed, Vector3(0.3, 0.42, 0.18), OLIVE)
		4:
			_pack(m, v, seed, Vector3(0.38, 0.6, 0.26), KHAKI)
		_:
			_drive(m, v, seed)
	return m


## A red pouch with a white cross and a strap.
func _medkit(m: VoxelModel, v: float, seed: int) -> void:
	var s := Vector3(0.22, 0.14, 0.08)
	m.setup(s + Vector3.ONE * v * 4.0, v)
	m.fill_box(Vector3(-s.x / 2, 0, -s.z / 2), Vector3(s.x / 2, s.y, s.z / 2), RED, 0.06, seed)
	m.fill_box(Vector3(-0.012, s.y * 0.2, -s.z / 2 - v), Vector3(0.012, s.y * 0.8, -s.z / 2), WHITE, 0.0, seed)
	m.fill_box(Vector3(-0.04, s.y / 2 - 0.012, -s.z / 2 - v), Vector3(0.04, s.y / 2 + 0.012, -s.z / 2), WHITE, 0.0, seed)
	m.fill_box(Vector3(-s.x / 2, s.y - 0.02, -s.z / 2 - v), Vector3(s.x / 2, s.y, s.z / 2 + v), STRAP, 0.04, seed)


## A vest front: a panel with `pouches` magazine pouches across it and shoulder straps.
func _rig(m: VoxelModel, v: float, seed: int, pouches: int) -> void:
	var w := 0.3 + 0.03 * pouches
	var s := Vector3(w, 0.34, 0.06)
	m.setup(Vector3(w, 0.46, 0.12) + Vector3.ONE * v * 4.0, v)
	m.fill_box(Vector3(-w / 2, 0, -0.02), Vector3(w / 2, s.y * 0.75, 0.02), OLIVE, 0.06, seed)
	for x in [-w / 2 + 0.03, w / 2 - 0.07]:
		m.fill_box(Vector3(x, s.y * 0.7, -0.02), Vector3(x + 0.04, s.y + 0.08, 0.02), STRAP, 0.05, seed)
	var pw := (w - 0.04) / pouches
	for i in pouches:
		var x0 := -w / 2 + 0.02 + i * pw
		m.fill_box(Vector3(x0 + 0.004, 0.02, -0.06), Vector3(x0 + pw - 0.004, 0.17, -0.02), OLIVE.darkened(0.12), 0.07, seed + i)
		m.fill_box(Vector3(x0 + 0.004, 0.15, -0.065), Vector3(x0 + pw - 0.004, 0.18, -0.02), OLIVE.darkened(0.25), 0.03, seed + i)
		m.fill_box(Vector3(x0 + pw / 2 - 0.008, 0.11, -0.068), Vector3(x0 + pw / 2 + 0.008, 0.15, -0.06), BUCKLE, 0.0, seed)


## A pack: body, top flap, a front pocket, two straps on the back.
func _pack(m: VoxelModel, v: float, seed: int, s: Vector3, colour: Color) -> void:
	m.setup(s + Vector3(0.02, 0.06, 0.08) + Vector3.ONE * v * 4.0, v)
	m.fill_box(Vector3(-s.x / 2, 0, -s.z / 2), Vector3(s.x / 2, s.y, s.z / 2), colour, 0.07, seed)
	m.fill_box(Vector3(-s.x / 2 - v, s.y * 0.78, -s.z / 2 - v), Vector3(s.x / 2 + v, s.y + 0.02, s.z / 2 + v), colour.darkened(0.15), 0.05, seed + 1)
	m.fill_box(Vector3(-s.x * 0.32, s.y * 0.1, -s.z / 2 - 0.05), Vector3(s.x * 0.32, s.y * 0.5, -s.z / 2), colour.darkened(0.08), 0.06, seed + 2)
	m.fill_box(Vector3(-0.015, s.y * 0.45, -s.z / 2 - 0.055), Vector3(0.015, s.y * 0.52, -s.z / 2 - 0.045), BUCKLE, 0.0, seed)
	for x in [-s.x * 0.3, s.x * 0.3 - 0.035]:
		m.fill_box(Vector3(x, s.y * 0.1, s.z / 2), Vector3(x + 0.035, s.y * 0.85, s.z / 2 + 0.025), STRAP, 0.04, seed)


## A rugged drive: dark case, metal end, a status light.
func _drive(m: VoxelModel, v: float, seed: int) -> void:
	var s := Vector3(0.09, 0.02, 0.04)
	m.setup(s + Vector3(0.03, 0.0, 0.0) + Vector3.ONE * v * 4.0, v)
	m.fill_box(Vector3(-s.x / 2, 0, -s.z / 2), Vector3(s.x / 2, s.y, s.z / 2), CASE, 0.04, seed)
	m.fill_box(Vector3(s.x / 2, s.y * 0.25, -s.z * 0.3), Vector3(s.x / 2 + 0.025, s.y * 0.75, s.z * 0.3), METAL, 0.03, seed)
	m.fill_box(Vector3(-s.x / 2 + 0.01, s.y, -0.004), Vector3(-s.x / 2 + 0.018, s.y + v, 0.004), LED, 0.0, seed)
