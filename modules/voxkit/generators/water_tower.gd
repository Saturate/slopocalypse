class_name VoxWaterTower
extends VoxGenerator
## A water tower: four steel legs with rings of bracing, a ladder up one side, and a round
## sheet-metal tank with a stepped cone roof. Centred on its legs, standing on the origin.

const STEEL := Color(0.36, 0.37, 0.38)
const TANK := Color(0.55, 0.58, 0.56)
const BAND := Color(0.42, 0.45, 0.44)
const ROOF := Color(0.4, 0.33, 0.28)
const LEG := 0.16
const ROOF_STEPS := 5


func title() -> String:
	return "Water tower"


func params() -> Array[Dictionary]:
	return [
		seed_param(),
		param("height", "Legs (m)", 4.0, 12.0, 0.5, 7.0),
		param("radius", "Tank radius (m)", 1.0, 3.0, 0.1, 1.6),
		param("tank", "Tank height (m)", 1.5, 4.0, 0.1, 2.6),
		voxel_param(0.06, 0.15, 0.1),
	]


func build(values: Dictionary) -> VoxelModel:
	var p := with_defaults(values)
	var seed := int(p["seed"])
	var h: float = p["height"]
	var r: float = p["radius"]
	var th: float = p["tank"]
	var v: float = p["voxel"]
	var m := new_model()
	var span := r * 2.0 + v * 6.0
	m.setup(Vector3(span, h + th + r * 0.8 + v * 4.0, span), v)
	m.set_material(VoxMaterials.index_of("sheet_metal"))
	var leg := r * 0.7
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var at := Vector3(sx * leg, 0.0, sz * leg)
			m.fill_box(at - Vector3(LEG / 2.0, 0.0, LEG / 2.0), at + Vector3(LEG / 2.0, h, LEG / 2.0), STEEL, 0.04, seed)
	# Rings of bracing between the legs.
	var bar := 0.08
	for k in 3:
		var y0 := h * (0.3 + 0.3 * k)
		for side in [-1.0, 1.0]:
			m.fill_box(Vector3(-leg, y0, side * leg - bar / 2.0), Vector3(leg, y0 + bar, side * leg + bar / 2.0), STEEL.darkened(0.1), 0.03, seed + k)
			m.fill_box(Vector3(side * leg - bar / 2.0, y0, -leg), Vector3(side * leg + bar / 2.0, y0 + bar, leg), STEEL.darkened(0.1), 0.03, seed + k)
	# A ladder up the +x side, just clear of the tank, from the ground to its rim.
	var lx := r + v
	m.fill_box(Vector3(lx, 0.0, -0.25), Vector3(lx + 0.06, h + th, -0.19), STEEL, 0.03, seed)
	m.fill_box(Vector3(lx, 0.0, 0.19), Vector3(lx + 0.06, h + th, 0.25), STEEL, 0.03, seed)
	var y := 0.3
	while y < h + th:
		m.fill_box(Vector3(lx, y, -0.2), Vector3(lx + 0.06, y + 0.05, 0.2), STEEL, 0.03, seed)
		y += 0.35
	# The tank, with darker bands round it, and its roof in steps.
	m.fill_cylinder(Vector3(0.0, h, 0.0), r, th, TANK, 0.05, seed)
	for k in 3:
		m.fill_cylinder(Vector3(0.0, h + th * (0.1 + 0.4 * k), 0.0), r + v * 0.5, v, BAND, 0.03, seed + k)
	for k in ROOF_STEPS:
		var share := 1.0 - float(k) / ROOF_STEPS
		m.fill_cylinder(Vector3(0.0, h + th + k * v * 1.5, 0.0), r * share + v, v * 1.5, ROOF, 0.05, seed + 10 + k)
	return m
