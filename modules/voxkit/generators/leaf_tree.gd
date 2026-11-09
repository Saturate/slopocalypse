class_name VoxLeafTree
extends VoxGenerator
## A broadleaf tree: a trunk that forks into branches, each ending in a clump of leaves
## around a central crown. Autumn turns the leaves orange and red; wither (a felled tree
## drying out) turns them dead brown and drops them until only bare branches are left.

const BARK := Color(0.36, 0.27, 0.2)
const SUMMER := [Color(0.24, 0.42, 0.18), Color(0.3, 0.48, 0.2), Color(0.2, 0.36, 0.16)]
const AUTUMN := [Color(0.85, 0.45, 0.12), Color(0.75, 0.22, 0.1), Color(0.9, 0.7, 0.2)]
const DEAD := [Color(0.42, 0.31, 0.16), Color(0.36, 0.26, 0.14), Color(0.48, 0.37, 0.2)]


func title() -> String:
	return "Leaf tree"


func params() -> Array[Dictionary]:
	return [
		seed_param(),
		param("height", "Height (m)", 3.0, 14.0, 0.5, 7.5),
		param("trunk", "Trunk width (m)", 0.2, 1.2, 0.05, 0.5),
		param("crown", "Crown size (m)", 1.2, 6.0, 0.1, 3.2),
		param("branches", "Branches", 2.0, 9.0, 1.0, 5.0),
		param("leafiness", "Leafiness", 0.2, 1.2, 0.05, 0.85),
		param("autumn", "Autumn", 0.0, 1.0, 0.05, 0.0),
		param("wither", "Wither", 0.0, 1.0, 0.05, 0.0),
		voxel_param(0.04, 0.3, 0.1),
	]


func build(values: Dictionary) -> VoxelModel:
	var p := with_defaults(values)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p["seed"])
	var seed := int(p["seed"])
	var h: float = p["height"]
	var crown: float = p["crown"]
	var trunk: float = p["trunk"]
	# Withered leaves fall: the clumps shrink to nothing.
	var leafy: float = float(p["leafiness"]) * (1.0 - float(p["wither"]))
	var min_clump := float(p["voxel"]) * 2.0
	var m := new_model()
	m.setup(Vector3(crown * 2.8 + 1.0, h + crown * 0.5 + 1.0, crown * 2.8 + 1.0), p["voxel"])
	var fork := Vector3(rng.randf_range(-0.2, 0.2), h * 0.42, rng.randf_range(-0.2, 0.2))
	m.fill_capsule(Vector3(0, -0.3, 0), fork, trunk * 0.5, trunk * 0.36, BARK, 0.15, seed)
	var middle := Vector3(0, h - crown * 0.55, 0)
	var count := int(p["branches"])
	var tips: Array[Vector3] = []
	for b in count:
		var angle := TAU * float(b) / count + rng.randf_range(-0.4, 0.4)
		var reach := crown * rng.randf_range(0.5, 0.85)
		var tip := middle + Vector3(cos(angle) * reach, crown * rng.randf_range(-0.35, 0.45), sin(angle) * reach)
		m.fill_capsule(fork, tip, trunk * 0.28, trunk * 0.1, BARK, 0.15, seed + b)
		tips.append(tip)
	# The colour is drawn either way, so the random sequence (and the branches) stay the same.
	var core_colour := _leaf(rng, p)
	if crown * 0.6 * leafy >= min_clump:
		m.fill_blob(middle, Vector3(crown * 0.8, crown * 0.6, crown * 0.8) * leafy, 0.3, 1.2, core_colour, 0.18, seed + 50)
	for i in tips.size():
		var size := crown * rng.randf_range(0.42, 0.62) * leafy
		var colour := _leaf(rng, p)
		if size * 0.8 >= min_clump:
			m.fill_blob(tips[i], Vector3(size, size * 0.8, size), 0.35, 1.6, colour, 0.2, seed + 60 + i)
	# Sun on top of the crown.
	var lit := _leaf(rng, p).lightened(0.18)
	if leafy > 0.0:
		m.paint_ellipsoid(middle + Vector3.UP * crown * 0.55, Vector3(crown * 1.1, crown * 0.45, crown * 1.1), lit, 0.2, seed + 99)
	return m


func _leaf(rng: RandomNumberGenerator, p: Dictionary) -> Color:
	var i := rng.randi_range(0, SUMMER.size() - 1)
	var summer: Color = SUMMER[i]
	var autumn: Color = AUTUMN[i]
	var dead: Color = DEAD[i]
	return summer.lerp(autumn, float(p["autumn"])).lerp(dead, float(p["wither"]))
