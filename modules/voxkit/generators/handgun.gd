class_name VoxHandgun
extends VoxGenerator
## Shared by the handgun generators (`VoxFiveSeven`, `VoxDesertEagle`, `VoxPython`): each
## draws its parts in gun space (the frame's origin, the barrel down -Z, y up), so the whole
## gun is all of them, and `cut` takes one part out around its mount, as `VoxMachineGun`
## does. A subclass lists its parts, mounts, bounds and finishes and draws each part in
## `_draw`; `mounts()` must match the receiver's `mounts` in the weapons data.

const BLUED := Color(0.13, 0.14, 0.16)
const DARK := Color(0.06, 0.06, 0.07)

## Gun space to model space for the part being built.
var _offset := Vector3.ZERO


## Labels for the library's part choice; the first is the whole gun.
func parts() -> Array[String]:
	return ["Whole gun"]


## `part_mesh` names, in the order of `parts()` after the whole gun.
func part_keys() -> Array[String]:
	return []


## Part key -> where its origin sits in gun space (its mount on the frame).
func mounts() -> Dictionary:
	return {}


## Part key -> its box in gun space; the whole gun's under "". The grid is fitted to it.
func bounds() -> Dictionary:
	return {}


func finishes() -> Array[String]:
	return ["Default"]


## The parts the whole gun is drawn with, in order: a later part fills over an earlier one
## where they overlap (a magazine inside the grip). A spare part (a longer magazine) is left
## out.
func draw_order() -> Array[String]:
	return part_keys()


func _draw(_m: VoxelModel, _key: String, _finish: int, _seed: int) -> void:
	pass


func params() -> Array[Dictionary]:
	return [
		seed_param(),
		choice("part", "Part", parts(), 0),
		choice("finish", "Finish", finishes(), 0),
		# Handguns are a quarter the length of a rifle, so their voxels are finer.
		param("voxel", "Voxel size (m)", 0.002, 0.006, 0.0005, 0.0025),
	]


func build(values: Dictionary) -> VoxelModel:
	var p := with_defaults(values)
	var seed := int(p["seed"])
	var m := new_model()
	var keys := part_keys()
	var part := clampi(int(p["part"]), 0, keys.size())
	var v := float(p["voxel"])
	var box: AABB = bounds()["" if part == 0 else keys[part - 1]]
	box = box.grow(v * 2.0)
	var half_x := maxf(absf(box.position.x), absf(box.end.x))
	m.setup(Vector3(half_x * 2.0, box.size.y, box.size.z), v)
	# The grid's x and z are centred and its y starts at 0.
	_offset = Vector3(0.0, -box.position.y, -box.get_center().z)
	var finish := clampi(int(p["finish"]), 0, finishes().size() - 1)
	var order := draw_order()
	if part > 0:
		order = [keys[part - 1]]
	for key in order:
		_draw(m, key, finish, seed)
	return m


## One part of `gen` as a mesh in its own space (origin at its mount), with the shared voxel
## material; null for an unknown part.
static func cut(gen: VoxHandgun, part: String) -> ArrayMesh:
	var index := gen.part_keys().find(part)
	if index < 0:
		return null
	VoxShading.ensure()
	var arrays := gen.build({"part": float(index + 1)}).mesh_arrays()
	var mesh := ArrayMesh.new()
	if arrays.is_empty():
		return mesh
	var to_part := -gen._offset - (gen.mounts()[part] as Vector3)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i] += to_part
	arrays[Mesh.ARRAY_VERTEX] = verts
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material())
	return mesh


func _g(at: Vector3) -> Vector3:
	return at + _offset


func _box(m: VoxelModel, lo: Vector3, hi: Vector3, colour: Color, seed: int) -> void:
	m.fill_box(_g(lo), _g(hi), colour, 0.0, seed)


func _paint(m: VoxelModel, lo: Vector3, hi: Vector3, colour: Color, seed: int) -> void:
	m.paint_box(_g(lo), _g(hi), colour, 0.0, seed)


func _carve(m: VoxelModel, lo: Vector3, hi: Vector3) -> void:
	m.carve_box(_g(lo), _g(hi))


func _rod(m: VoxelModel, a: Vector3, b: Vector3, radius: float, colour: Color, seed: int) -> void:
	m.fill_capsule(_g(a), _g(b), radius, radius, colour, 0.0, seed)


## A round tube along Z through `axis` (x, y) from `z_back` to `z_front` (z_front < z_back)
## with flat ends: a thin disc per row of voxels, so nothing outside it is cut, unlike a
## capsule with its ends carved off.
func _tube(m: VoxelModel, axis: Vector3, z_back: float, z_front: float, radius: float, colour: Color, seed: int) -> void:
	var step := m.voxel_size()
	var z := z_front + step * 0.5
	while z < z_back:
		m.fill_ellipsoid(_g(Vector3(axis.x, axis.y, z)), Vector3(radius, radius, step * 0.6), colour, 0.0, seed)
		z += step


## The bore at a muzzle: dark inside, open at the front face `z`.
func _bore(m: VoxelModel, at: Vector3, radius: float) -> void:
	m.paint_ellipsoid(_g(at), Vector3(radius + 0.001, radius + 0.001, 0.02), DARK, 0.0, 0)
	m.carve_ellipsoid(_g(at), Vector3(radius, radius, 0.008))


## A grip: one voxel-thick slice per row from `top` down to `bottom` (y), its front and back
## edges running straight from (`front_top`, `back_top`) to (`front_bottom`, `back_bottom`)
## (z), `half` wide each side. `round` rounds the bottom corners off by that much.
func _grip(m: VoxelModel, top: float, bottom: float, front_top: float, front_bottom: float, back_top: float, back_bottom: float, half: float, colour: Color, seed: int, round := 0.0) -> void:
	var step := m.voxel_size()
	var y := bottom
	while y < top:
		var t := (top - y) / (top - bottom)
		var front := lerpf(front_top, front_bottom, t)
		var back := lerpf(back_top, back_bottom, t)
		var inset := 0.0
		if round > 0.0 and y - bottom < round:
			var u := 1.0 - (y - bottom) / round
			inset = round * (1.0 - sqrt(maxf(1.0 - u * u, 0.0)))
		_box(m, Vector3(-half, y, front + inset), Vector3(half, y + step, back - inset), colour, seed)
		y += step


## Rear sight: two ears either side of a notch whose bottom is on `sight_line`, at `z`.
func _rear_sight(m: VoxelModel, base: float, sight_line: float, z: float, half: float, seed: int) -> void:
	_box(m, Vector3(-half, base, z - 0.004), Vector3(half, sight_line + 0.004, z + 0.004), DARK, seed)
	_carve(m, Vector3(-0.0025, sight_line, z - 0.005), Vector3(0.0025, sight_line + 0.006, z + 0.005))
