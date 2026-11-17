class_name VoxStreetLamp
extends VoxGenerator
## A street lamp: a concrete foot, a square steel post, an arm reaching out along +x and a
## flat head with a glass bulb under it (the `bulb` material, which breaks like window glass).
## The post stands on the origin; the arm reaches toward whatever it lights.

const STEEL := Color(0.3, 0.32, 0.34)
const FOOT := Color(0.58, 0.57, 0.54)
const BULB := Color(1.0, 0.92, 0.72)
const FOOT_SIZE := Vector3(0.4, 0.3, 0.4)
const POST := 0.15
const HEAD := Vector3(0.8, 0.14, 0.34)
const BULB_SIZE := Vector3(0.6, 0.1, 0.25)


func title() -> String:
	return "Street lamp"


func params() -> Array[Dictionary]:
	return [
		seed_param(),
		param("height", "Height (m)", 2.5, 7.0, 0.1, 4.5),
		param("reach", "Arm reach (m)", 0.3, 3.5, 0.05, 2.6),
		voxel_param(0.04, 0.1, 0.05),
	]


func build(values: Dictionary) -> VoxelModel:
	var p := with_defaults(values)
	var seed := int(p["seed"])
	var h: float = p["height"]
	var reach: float = p["reach"]
	var v: float = p["voxel"]
	var m := new_model()
	# Centred on x and z, so it spans the arm both ways; the far side stays empty.
	var half := reach + HEAD.x / 2.0 + v * 2.0
	m.setup(Vector3(half * 2.0, h + v * 4.0, maxf(FOOT_SIZE.z, HEAD.z) + v * 4.0), v)
	m.set_material(VoxMaterials.index_of("concrete"))
	m.fill_box(Vector3(-FOOT_SIZE.x / 2.0, 0.0, -FOOT_SIZE.z / 2.0), Vector3(FOOT_SIZE.x / 2.0, FOOT_SIZE.y, FOOT_SIZE.z / 2.0), FOOT, 0.08, seed)
	m.set_material(VoxMaterials.index_of("sheet_metal"))
	m.fill_box(Vector3(-POST / 2.0, FOOT_SIZE.y, -POST / 2.0), Vector3(POST / 2.0, h, POST / 2.0), STEEL, 0.04, seed)
	var arm := POST * 0.6
	m.fill_box(Vector3(-POST / 2.0, h - arm, -arm / 2.0), Vector3(reach, h, arm / 2.0), STEEL, 0.04, seed + 1)
	var head_lo := Vector3(reach - HEAD.x / 2.0, h - HEAD.y, -HEAD.z / 2.0)
	m.fill_box(head_lo, head_lo + HEAD, STEEL.darkened(0.15), 0.03, seed + 2)
	var bulb_lo := Vector3(reach - BULB_SIZE.x / 2.0, h - HEAD.y - BULB_SIZE.y, -BULB_SIZE.z / 2.0)
	m.set_material(VoxMaterials.index_of("bulb"))
	m.fill_box(bulb_lo, bulb_lo + BULB_SIZE, BULB, 0.0, seed)
	return m
