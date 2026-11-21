class_name VoxSubstation
extends VoxGenerator
## An electrical substation's yard: a gravel pad on a concrete plinth (as tall as `plinth`,
## so it can stand level on sloping ground), a steel post-and-rail fence round it with a gate
## gap in the middle of the front (-z) side, two transformers with radiator fins in the middle
## and a small control hut in a back corner. The terminal gantries the lines come in on are
## pieces of their own (VoxTerminalGantry). Centred on its pad, standing on the origin; the
## pad's top is `plinth` up.

const GRAVEL := Color(0.55, 0.54, 0.5)
const CONCRETE := Color(0.6, 0.59, 0.56)
const STEEL := Color(0.45, 0.47, 0.48)
const TRANSFORMER := Color(0.36, 0.4, 0.37)
const FIN := Color(0.3, 0.33, 0.31)
const HUT := Color(0.66, 0.62, 0.54)
const ROOF := Color(0.32, 0.3, 0.3)
const FENCE_HEIGHT := 2.2
const POST_STEP := 3.0
const POST := 0.1
const RAIL := 0.06
const GATE := 5.0
## Metres in from the pad's edge the fence stands.
const FENCE_INSET := 0.4
const TRANSFORMER_SIZE := Vector3(3.0, 2.6, 2.4)
## Metres between the two transformers' middles.
const TRANSFORMER_GAP := 6.0
const HUT_SIZE := Vector3(4.0, 2.8, 3.0)


func title() -> String:
	return "Substation"


func params() -> Array[Dictionary]:
	return [
		seed_param(),
		param("size", "Yard size (m)", 20.0, 48.0, 1.0, 32.0),
		param("plinth", "Plinth height (m)", 0.2, 3.0, 0.05, 0.6),
		voxel_param(0.1, 0.25, 0.15),
	]


## Collision boxes (model space): the plinth, the fence with its gate gap, the transformers
## and the hut.
static func collision(values: Dictionary) -> Array[AABB]:
	var p := VoxSubstation.new().with_defaults(values)
	var half := float(p["size"]) / 2.0
	var top: float = p["plinth"]
	var out: Array[AABB] = [AABB(Vector3(-half, 0.0, -half), Vector3(half * 2.0, top, half * 2.0))]
	var f := half - FENCE_INSET
	var t := POST
	out.append(AABB(Vector3(-f, top, f - t), Vector3(f * 2.0, FENCE_HEIGHT, t * 2.0)))
	out.append(AABB(Vector3(-f, top, -f), Vector3(t * 2.0, FENCE_HEIGHT, f * 2.0)))
	out.append(AABB(Vector3(f - t * 2.0, top, -f), Vector3(t * 2.0, FENCE_HEIGHT, f * 2.0)))
	# The front either side of the gate.
	var side := f - GATE / 2.0
	out.append(AABB(Vector3(-f, top, -f - t), Vector3(side, FENCE_HEIGHT, t * 2.0)))
	out.append(AABB(Vector3(GATE / 2.0, top, -f - t), Vector3(side, FENCE_HEIGHT, t * 2.0)))
	for x: float in [-TRANSFORMER_GAP / 2.0, TRANSFORMER_GAP / 2.0]:
		out.append(AABB(Vector3(x - TRANSFORMER_SIZE.x / 2.0, top, -TRANSFORMER_SIZE.z / 2.0), TRANSFORMER_SIZE))
	out.append(AABB(_hut_at(half, top), HUT_SIZE))
	return out


static func _hut_at(half: float, top: float) -> Vector3:
	return Vector3(half - FENCE_INSET - 1.0 - HUT_SIZE.x, top, half - FENCE_INSET - 1.0 - HUT_SIZE.z)


func build(values: Dictionary) -> VoxelModel:
	var p := with_defaults(values)
	var seed := int(p["seed"])
	var half := float(p["size"]) / 2.0
	var top: float = p["plinth"]
	var v: float = p["voxel"]
	var m := new_model()
	m.setup(Vector3(half * 2.0 + v * 4.0, top + FENCE_HEIGHT + TRANSFORMER_SIZE.y + v * 4.0, half * 2.0 + v * 4.0), v)
	m.set_material(VoxMaterials.index_of("concrete"))
	m.fill_box(Vector3(-half, 0.0, -half), Vector3(half, top - v, half), CONCRETE, 0.06, seed)
	m.fill_box(Vector3(-half, top - v, -half), Vector3(half, top, half), GRAVEL, 0.18, seed + 1)
	m.set_material(VoxMaterials.index_of("sheet_metal"))
	var f := half - FENCE_INSET
	var corners: Array[Vector3] = [Vector3(-f, top, -f), Vector3(f, top, -f), Vector3(f, top, f), Vector3(-f, top, f)]
	var post_r := maxf(POST / 2.0, v * 0.6)
	var rail_r := maxf(RAIL / 2.0, v * 0.5)
	for k in 4:
		var a := corners[k]
		var b := corners[(k + 1) % 4]
		var length := a.distance_to(b)
		var posts := maxi(ceili(length / POST_STEP), 1)
		# The front (the first side, a to b along +x) has the gate in its middle.
		var gate := k == 0
		for i in posts + 1:
			var at := a.lerp(b, float(i) / posts)
			if gate and absf(at.x) < GATE / 2.0 - 0.01:
				continue
			m.fill_box(at - Vector3(post_r, 0.0, post_r), at + Vector3(post_r, FENCE_HEIGHT, post_r), STEEL, 0.03, seed)
		for y: float in [0.6, 1.4, FENCE_HEIGHT - rail_r]:
			if gate:
				for piece: Array in [[a, Vector3(-GATE / 2.0, top, a.z)], [Vector3(GATE / 2.0, top, a.z), b]]:
					m.fill_capsule((piece[0] as Vector3) + Vector3.UP * y, (piece[1] as Vector3) + Vector3.UP * y, rail_r, rail_r, STEEL, 0.03, seed)
			else:
				m.fill_capsule(a + Vector3.UP * y, b + Vector3.UP * y, rail_r, rail_r, STEEL, 0.03, seed)
	for x: float in [-TRANSFORMER_GAP / 2.0, TRANSFORMER_GAP / 2.0]:
		var lo := Vector3(x - TRANSFORMER_SIZE.x / 2.0, top, -TRANSFORMER_SIZE.z / 2.0)
		m.fill_box(lo, lo + TRANSFORMER_SIZE, TRANSFORMER, 0.04, seed + 2)
		# Radiator fins down both long sides.
		var fins := int(TRANSFORMER_SIZE.x / 0.4)
		for i in fins:
			var fx := lo.x + 0.2 + i * 0.4
			for z: float in [lo.z - 0.25, lo.z + TRANSFORMER_SIZE.z]:
				m.fill_box(Vector3(fx, top + 0.3, z), Vector3(fx + v, top + TRANSFORMER_SIZE.y - 0.3, z + 0.25), FIN, 0.02, seed + 3)
		# Bushings on top.
		for i in 3:
			var bx := lo.x + 0.6 + i * 0.9
			m.fill_capsule(Vector3(bx, top + TRANSFORMER_SIZE.y, 0.0), Vector3(bx, top + TRANSFORMER_SIZE.y + 0.9, 0.0), 0.1, 0.07, Color(0.82, 0.8, 0.74), 0.02, seed)
	m.set_material(VoxMaterials.index_of("brick"))
	var hut := _hut_at(half, top)
	m.fill_box(hut, hut + HUT_SIZE, HUT, 0.06, seed + 4)
	m.set_material(VoxMaterials.index_of("concrete"))
	m.fill_box(hut + Vector3(-0.2, HUT_SIZE.y, -0.2), hut + HUT_SIZE + Vector3(0.2, 0.25, 0.2), ROOF, 0.03, seed + 5)
	return m
