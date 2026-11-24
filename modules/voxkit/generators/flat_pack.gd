class_name VoxFlatPack
extends VoxGenerator
## Flat-pack furniture boxes from the BLÅGUL store: long, flat cardboard boxes with tape
## across the ends, a blue band round one end and a yellow label on it, stacked a little out
## of line. Sizes are a shelf's worth (long and narrow), a table top (wide) or a small box.
## Standing on y 0, centred; `collision` is the stack's box.

const SIZES: Array[String] = ["Long", "Wide", "Small"]
## Each size, metres (length along x, height, depth along z).
const BOXES := [Vector3(1.8, 0.12, 0.45), Vector3(1.4, 0.1, 0.8), Vector3(0.6, 0.2, 0.4)]
const CARDBOARD := Color(0.69, 0.55, 0.38)
const TAPE := Color(0.78, 0.68, 0.5)
const BLUE := Color(0.05, 0.25, 0.55)
const YELLOW := Color(0.98, 0.82, 0.1)
## Boxes in a stack shift up to this much from the one under them, metres.
const SHIFT := 0.04


func title() -> String:
	return "Flat-pack boxes"


func params() -> Array[Dictionary]:
	return [
		seed_param(),
		choice("size", "Size", SIZES, 0),
		param("count", "Boxes", 1.0, 8.0, 1.0, 3.0),
		voxel_param(0.015, 0.05, 0.02),
	]


static func box_size(values: Dictionary) -> Vector3:
	var p := VoxFlatPack.new().with_defaults(values)
	return BOXES[clampi(int(p["size"]), 0, BOXES.size() - 1)]


static func collision(values: Dictionary) -> Array[AABB]:
	var p := VoxFlatPack.new().with_defaults(values)
	var s := box_size(p)
	var h := s.y * float(int(p["count"]))
	return [AABB(Vector3(-s.x / 2.0 - SHIFT, 0.0, -s.z / 2.0 - SHIFT), Vector3(s.x + SHIFT * 2.0, h, s.z + SHIFT * 2.0))]


func build(values: Dictionary) -> VoxelModel:
	var p := with_defaults(values)
	var seed := int(p["seed"])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var s := box_size(p)
	var count := int(p["count"])
	var v: float = p["voxel"]
	var m := new_model()
	m.setup(Vector3(s.x + SHIFT * 2.0 + v * 4.0, s.y * count + v * 2.0, s.z + SHIFT * 2.0 + v * 4.0), v)
	for i in count:
		var at := Vector3(rng.randf_range(-SHIFT, SHIFT), s.y * i, rng.randf_range(-SHIFT, SHIFT))
		draw(m, at, s, rng.randf() < 0.5, seed + i)
	return m


## One box with its bottom middle at `at`, `size` metres, the label on the -x end or (with
## `flip`) the +x end. For any generator that puts flat packs somewhere (shelving).
static func draw(m: VoxelModel, at: Vector3, size: Vector3, flip: bool, seed: int) -> void:
	m.set_material(VoxMaterials.index_of("furniture"))
	var h := size / 2.0
	var lo := Vector3(at.x - h.x, at.y, at.z - h.z)
	var hi := Vector3(at.x + h.x, at.y + size.y, at.z + h.z)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	m.fill_box(lo, hi, CARDBOARD * rng.randf_range(0.92, 1.06), 0.05, seed)
	var end := 1.0 if flip else -1.0
	var band := minf(size.x * 0.18, 0.3)
	var x0 := at.x + end * (h.x - band)
	var x1 := at.x + end * h.x
	m.paint_box(Vector3(minf(x0, x1) - 0.01, lo.y - 0.01, lo.z - 0.01), Vector3(maxf(x0, x1) + 0.01, hi.y + 0.01, hi.z + 0.01), BLUE, 0.02, seed)
	# The label on top of the band, on the end's top face and side.
	var lx0 := at.x + end * (h.x - band * 0.8)
	var lx1 := at.x + end * (h.x - band * 0.2)
	m.paint_box(Vector3(minf(lx0, lx1), hi.y - 0.02, at.z - h.z * 0.5), Vector3(maxf(lx0, lx1), hi.y + 0.01, at.z + h.z * 0.3), YELLOW, 0.0, seed)
	m.paint_box(Vector3(minf(lx0, lx1), lo.y + size.y * 0.25, lo.z - 0.01), Vector3(maxf(lx0, lx1), lo.y + size.y * 0.75, lo.z + 0.02), YELLOW, 0.0, seed)
	# Tape across the far end.
	var tx := at.x - end * (h.x - 0.12)
	m.paint_box(Vector3(tx - 0.04, lo.y - 0.01, lo.z - 0.01), Vector3(tx + 0.04, hi.y + 0.01, hi.z + 0.01), TAPE, 0.02, seed)
