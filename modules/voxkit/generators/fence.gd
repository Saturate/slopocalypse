class_name VoxFence
extends VoxGenerator
## A straight wooden fence: square posts every `post_step` metres with horizontal planks
## nailed across their front, each post and plank its own shade of weathered wood. The end
## posts can stand taller and thicker with a cap (corners and gateposts). Runs along x,
## centred, standing on the origin; the planks are on the -z face.

const WOOD := Color(0.47, 0.37, 0.26)
const POST_WOOD := Color(0.36, 0.28, 0.2)
const CAP := Color(0.3, 0.23, 0.17)
const POST := 0.16
const END_POST := 0.28
## Metres the end posts stand above the planks.
const END_RISE := 0.5
const PLANK_TALL := 0.2
const PLANK_THICK := 0.06
## Metres the top plank sits under the posts' tops.
const TOP_GAP := 0.12
## Metres the posts are thick in the collision box, with the planks.
const DEPTH := 0.3


func title() -> String:
	return "Fence"


func params() -> Array[Dictionary]:
	return [
		seed_param(),
		param("length", "Length (m)", 1.0, 40.0, 0.25, 8.0),
		param("height", "Height (m)", 0.8, 2.4, 0.05, 1.5),
		param("post_step", "Post spacing (m)", 1.2, 4.0, 0.1, 2.4),
		param("planks", "Planks", 1.0, 5.0, 1.0, 3.0),
		choice("tall_ends", "Tall end posts", ["No", "Yes"], 1),
		voxel_param(0.04, 0.15, 0.06),
	]


## One box over the whole run: posts and planks block as a wall would (the gaps between
## planks are too narrow to walk through).
static func collision(values: Dictionary) -> Array[AABB]:
	var p := VoxFence.new().with_defaults(values)
	var length: float = p["length"]
	var h: float = p["height"]
	var out: Array[AABB] = [AABB(Vector3(-length / 2.0, 0.0, -DEPTH / 2.0), Vector3(length, h, DEPTH))]
	if int(p["tall_ends"]) == 1:
		for x: float in [-length / 2.0, length / 2.0 - END_POST]:
			out.append(AABB(Vector3(x, 0.0, -END_POST / 2.0), Vector3(END_POST, h + END_RISE, END_POST)))
	return out


func build(values: Dictionary) -> VoxelModel:
	var p := with_defaults(values)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p["seed"])
	var seed := int(p["seed"])
	var length: float = p["length"]
	var h: float = p["height"]
	var v: float = p["voxel"]
	var tall := int(p["tall_ends"]) == 1
	var m := new_model()
	m.setup(Vector3(length + v * 4.0, h + END_RISE + v * 4.0, END_POST + v * 4.0), v)
	m.set_material(VoxMaterials.index_of("wood"))
	var half := length / 2.0
	# Posts evenly spaced, as near `post_step` apart as the length allows.
	var gaps := maxi(roundi(length / float(p["post_step"])), 1)
	for i in gaps + 1:
		var x := -half + length * float(i) / gaps
		var end := i == 0 or i == gaps
		var w := END_POST if end and tall else POST
		var top := h + (END_RISE if end and tall else rng.randf_range(-0.04, 0.06))
		x = clampf(x, -half + w / 2.0, half - w / 2.0)
		m.fill_box(Vector3(x - w / 2.0, 0.0, -w / 2.0), Vector3(x + w / 2.0, top, w / 2.0), POST_WOOD * rng.randf_range(0.85, 1.08), 0.06, seed + i)
		if end and tall:
			m.fill_box(Vector3(x - w / 2.0 - v, top, -w / 2.0 - v), Vector3(x + w / 2.0 + v, top + v * 1.5, w / 2.0 + v), CAP, 0.04, seed + 90)
	# Planks across the posts' front, from the top down, each a little different.
	var planks := int(p["planks"])
	var top_y := h - TOP_GAP - PLANK_TALL
	var step := (top_y - 0.2) / maxf(planks - 1, 1)
	for k in planks:
		var y := top_y - step * k
		var z0 := -POST / 2.0 - PLANK_THICK
		var sag := rng.randf_range(-0.03, 0.03)
		m.fill_box(Vector3(-half, y + sag, z0 - v * 0.5), Vector3(half, y + sag + PLANK_TALL, -POST / 2.0), WOOD * rng.randf_range(0.82, 1.1), 0.08, seed + 20 + k)
	return m
