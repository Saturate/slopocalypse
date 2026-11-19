class_name LimbPieces
extends RefCounted
## Cuts limbs out of a body's skinned meshes (#387). Every part of the body is weighted fully
## to one bone, so a limb is exactly the triangles whose vertices belong to its bones. A piece
## is laid out in the bind space of the bone it is cut at (the joint at its origin), as the
## body stands at rest. Pieces and per-bone boxes are worked out once per mesh and kept, so a
## death never builds a mesh.

## Filed by the mesh's instance id, which is only safe while that mesh stays loaded:
## LimbSevering holds the body scene for as long as it runs, so its meshes (and these ids)
## live as long as the caches do.
## Mesh instance id + limb -> the piece (or null when that mesh has none of the limb).
static var _pieces: Dictionary = {}
## Distances within this many metres of each other count as a tie.
const TIE := 0.005
## A point further than this from every part is not on the body (a bullet stops on its
## capsule, which stands no further off any part than this).
const REACH := 0.4
## Mesh instance id -> {bone index: AABB of its own vertices in its bind space}.
static var _boxes: Dictionary = {}


## The part of `source` (a skinned MeshInstance3D on `skeleton`) belonging to `limb`'s bones,
## in the bind space of its root bone; null when this mesh has none of it.
static func piece(source: MeshInstance3D, skeleton: Skeleton3D, limb: String) -> ArrayMesh:
	var key := "%d:%s" % [source.mesh.get_instance_id(), limb]
	if _pieces.has(key):
		return _pieces[key]
	var made := _cut(source, skeleton, limb)
	_pieces[key] = made
	return made


## For each bone of `skeleton` that `source` has vertices on: the box round them in that
## bone's own space, to tell which bone a point on the body is nearest.
static func bone_boxes(source: MeshInstance3D, skeleton: Skeleton3D) -> Dictionary:
	var key := source.mesh.get_instance_id()
	if _boxes.has(key):
		return _boxes[key]
	var boxes := {}
	var arrays := source.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var binds := _vertex_binds(arrays)
	for v in verts.size():
		var bind := binds[v]
		var bone := _bone_of(source.skin, skeleton, bind)
		if bone < 0:
			continue
		var at := source.skin.get_bind_pose(bind) * verts[v]
		boxes[bone] = (boxes[bone] as AABB).expand(at) if boxes.has(bone) else AABB(at, Vector3.ZERO)
	_boxes[key] = boxes
	return boxes


## The bone of `skeleton` nearest `point` (world space) by the meshes in `sources`, posed as
## the skeleton stands now; -1 without any, or when the point is off the body.
static func nearest_bone(sources: Array[MeshInstance3D], skeleton: Skeleton3D, point: Vector3) -> int:
	var best := -1
	var best_d := INF
	var best_centre := INF
	for source in sources:
		var boxes := bone_boxes(source, skeleton)
		for bone: int in boxes:
			var pose := skeleton.global_transform * skeleton.get_bone_global_pose(bone)
			var local := pose.affine_inverse() * point
			var box: AABB = boxes[bone]
			var d := local.distance_to(local.clamp(box.position, box.end))
			# Inside more than one box (a hand held against the chest's pouches): the part whose
			# middle it is nearest.
			var centre := local.distance_to(box.get_center())
			if d < best_d - TIE or (d <= best_d + TIE and centre < best_centre):
				best_d = d
				best_centre = centre
				best = bone
	return best if best_d <= REACH else -1


static func _cut(source: MeshInstance3D, skeleton: Skeleton3D, limb: String) -> ArrayMesh:
	var wanted := {}
	for bone_name: String in LimbRules.bones(limb):
		var bone := skeleton.find_bone(bone_name)
		if bone >= 0:
			wanted[bone] = true
	var root := skeleton.find_bone(LimbRules.root_bone(limb))
	var root_bind := _bind_of(source.skin, skeleton, root)
	if root_bind < 0 or source.mesh == null:
		return null
	var to_root := source.skin.get_bind_pose(root_bind)
	var arrays := source.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if indices.is_empty():
		indices.resize(verts.size())
		for i in verts.size():
			indices[i] = i
	var binds := _vertex_binds(arrays)
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	var out_c := PackedColorArray()
	for t in range(0, indices.size() - 2, 3):
		var keep := true
		for k in 3:
			if not wanted.has(_bone_of(source.skin, skeleton, binds[indices[t + k]])):
				keep = false
				break
		if not keep:
			continue
		for k in 3:
			var v := indices[t + k]
			out_v.append(to_root * verts[v])
			out_n.append((to_root.basis * normals[v]).normalized())
			out_c.append(colours[v] if not colours.is_empty() else Color.WHITE)
	if out_v.is_empty():
		return null
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = out_v
	out[Mesh.ARRAY_NORMAL] = out_n
	out[Mesh.ARRAY_COLOR] = out_c
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	mesh.surface_set_material(0, source.mesh.surface_get_material(0))
	return mesh


## Per vertex: the skin bind it is weighted to most (fully, for this body).
static func _vertex_binds(arrays: Array) -> PackedInt32Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	@warning_ignore("integer_division")
	var per := bones.size() / maxi(verts.size(), 1)
	var out := PackedInt32Array()
	out.resize(verts.size())
	for v in verts.size():
		var best := 0
		for k in per:
			if weights[v * per + k] > weights[v * per + best]:
				best = k
		out[v] = bones[v * per + best]
	return out


static func _bone_of(skin: Skin, skeleton: Skeleton3D, bind: int) -> int:
	var bone := skin.get_bind_bone(bind)
	return bone if bone >= 0 else skeleton.find_bone(skin.get_bind_name(bind))


static func _bind_of(skin: Skin, skeleton: Skeleton3D, bone: int) -> int:
	for bind in skin.get_bind_count():
		if _bone_of(skin, skeleton, bind) == bone:
			return bind
	return -1
