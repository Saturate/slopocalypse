class_name VoxelVolume
extends MeshInstance3D
## Draws a `VoxelModel` on the GPU instead of as a mesh (#306): its cells go into 3D
## textures and `voxel_volume.gdshader` finds the first filled cell along each pixel's ray, so
## the cost follows screen pixels, not the number of voxels or faces. Only the BRICK-cell
## cubes that hold anything are uploaded, packed into an atlas with two bytes a cell, plus an
## indirection texture saying where each brick went (about a seventh of the dense grid's
## memory for a building). Volumes showing the same model share one upload and one material,
## so a street of the same building costs one building's memory. The node's origin is the
## model's origin (x and z centred, y from the ground), like a mesh of the same model. Client
## only.

const SHADER := preload("res://modules/voxkit/shaders/voxel_volume.gdshader")
## Cells per side of a brick; the shader's BRICK must match.
const BRICK := 4
## Bricks per row and column of the atlas (a 128 x 128 cell layer).
const ATLAS_ROW := 32

var model: VoxelModel
## Bytes this volume's model takes on the GPU (shared with other volumes of the same model),
## after `refresh`.
var gpu_bytes := 0

## Per model (by instance id), what its volumes share: `{indirection, atlas, mesh, material,
## bytes, users}`. Dropped when the last volume showing it leaves the tree.
static var _shared: Dictionary[int, Dictionary] = {}

var _key := 0


## Uploads the model's cells and sizes the box to it, or picks up what another volume of the
## same model already uploaded; call after building it. After editing a shared model, call
## with `force` so every volume showing it sees the edit.
func refresh(force := false) -> void:
	var t := Prof.start()
	_release()
	if model == null or model.voxel_count() == 0:
		mesh = null
		material_override = null
		gpu_bytes = 0
		return
	_key = model.get_instance_id()
	var entry: Dictionary = _shared.get(_key, {})
	if entry.is_empty() or force:
		entry = _upload(model, entry)
		_shared[_key] = entry
	entry["users"] = int(entry.get("users", 0)) + 1
	mesh = entry["mesh"]
	material_override = entry["material"]
	gpu_bytes = entry["bytes"]
	Prof.stop(&"voxkit/volume_upload", t)


func _exit_tree() -> void:
	_release()


func _release() -> void:
	if _key == 0 or not _shared.has(_key):
		_key = 0
		return
	var entry := _shared[_key]
	entry["users"] = int(entry["users"]) - 1
	if int(entry["users"]) <= 0:
		_shared.erase(_key)
	_key = 0


## The textures, box and material for `m`, reusing `into`'s textures and material if given.
static func _upload(m: VoxelModel, into: Dictionary) -> Dictionary:
	var n := m.cells()
	var v := m.voxel_size()
	var packed := m.brick_atlas(BRICK, ATLAS_ROW)
	var indirection := _texture_3d(packed["indirection"], packed["bricks"], Image.FORMAT_RGBA8, 4, into.get("indirection"))
	var atlas := _texture_3d(packed["atlas"], packed["cells"], Image.FORMAT_RG8, 2, into.get("atlas"))
	var extent := Vector3(n) * v
	var material: ShaderMaterial = into.get("material", null)
	if material == null:
		material = ShaderMaterial.new()
		material.shader = SHADER
	material.set_shader_parameter("indirection", indirection)
	material.set_shader_parameter("atlas", atlas)
	material.set_shader_parameter("size", n)
	material.set_shader_parameter("voxel", v)
	material.set_shader_parameter("origin", Vector3(-extent.x / 2.0, 0.0, -extent.z / 2.0))
	VoxShading.ensure()
	var levels := VoxShading.levels
	material.set_shader_parameter("corner_levels", Vector4(levels[0], levels[1], levels[2], levels[3]) if levels.size() == 4 else Vector4.ONE)
	return {
		"indirection": indirection, "atlas": atlas, "material": material, "mesh": _box(extent),
		"bytes": (packed["indirection"] as PackedByteArray).size() + (packed["atlas"] as PackedByteArray).size(),
		"users": into.get("users", 0),
	}


## A 3D texture of `size` texels from `bytes` laid out as z slices of y rows of x.
static func _texture_3d(bytes: PackedByteArray, size: Vector3i, format: Image.Format, texel: int, into: Variant) -> ImageTexture3D:
	var layer := size.x * size.y * texel
	var images: Array[Image] = []
	for z in size.z:
		images.append(Image.create_from_data(size.x, size.y, false, format, bytes.slice(z * layer, (z + 1) * layer)))
	var out: ImageTexture3D = into if into is ImageTexture3D else ImageTexture3D.new()
	out.create(format, size.x, size.y, size.z, false, images)
	return out


## The first filled cell along a ray in the model's space, found the way the shader finds it
## (keep the two in step, empty-brick jumps included): `{cell: Vector3i, normal: Vector3,
## point: Vector3}`, or empty when the ray misses. Tests check the shader's walk with it;
## gameplay can use it for rays against voxels. `bricks` is `model.brick_occupancy(BRICK)`,
## passed in so repeated casts don't rebuild it.
static func cast(model: VoxelModel, from: Vector3, direction: Vector3, bricks: PackedByteArray) -> Dictionary:
	var counts := model.brick_counts(BRICK)
	var n := model.cells()
	var v := model.voxel_size()
	var origin := Vector3(-n.x * v / 2.0, 0.0, -n.z * v / 2.0)
	var o := (from - origin) / v
	var d := direction.normalized()
	for a in 3:
		if d[a] == 0.0:
			d[a] = 1e-6
	var inv := Vector3(1.0 / d.x, 1.0 / d.y, 1.0 / d.z)
	var t_low := -o * inv
	var t_high := (Vector3(n) - o) * inv
	var t_near := t_low.min(t_high)
	var t_far := t_low.max(t_high)
	var enter := maxf(maxf(t_near.x, t_near.y), t_near.z)
	var leave := minf(minf(t_far.x, t_far.y), t_far.z)
	if leave < maxf(enter, 0.0):
		return {}
	var t := maxf(enter, 0.0)
	var step := Vector3i(signi(int(signf(d.x))), signi(int(signf(d.y))), signi(int(signf(d.z))))
	var t_delta := inv.abs()
	var p := o + d * (t + 1e-4)
	var cell := Vector3i(floori(p.x), floori(p.y), floori(p.z)).clamp(Vector3i.ZERO, n - Vector3i.ONE)
	var t_next := (Vector3(cell) + Vector3(step).max(Vector3.ZERO) - o) * inv
	var normal := Vector3.ZERO
	for a in 3:
		if t_near[a] == enter:
			normal[a] = -step[a]
	if enter < 0.0:
		normal = -d
	for i in n.x + n.y + n.z:
		var brick := cell / BRICK
		if bricks[(brick.z * counts.y + brick.y) * counts.x + brick.x] == 0:
			var low := Vector3(brick * BRICK)
			var bound := low
			for a in 3:
				if d[a] > 0.0:
					bound[a] += BRICK
			var t_out := (bound - o) * inv
			var axis_out := 2
			if t_out.x <= t_out.y and t_out.x <= t_out.z:
				axis_out = 0
			elif t_out.y <= t_out.z:
				axis_out = 1
			t = t_out[axis_out]
			var q := o + d * t
			cell = Vector3i(floori(q.x), floori(q.y), floori(q.z))
			cell[axis_out] = int(bound[axis_out]) if step[axis_out] > 0 else int(low[axis_out]) - 1
			t_next = (Vector3(cell) + Vector3(step).max(Vector3.ZERO) - o) * inv
			normal = Vector3.ZERO
			normal[axis_out] = -step[axis_out]
			if cell.x < 0 or cell.y < 0 or cell.z < 0 or cell.x >= n.x or cell.y >= n.y or cell.z >= n.z:
				break
			continue
		if model.is_filled(cell.x, cell.y, cell.z):
			return {"cell": cell, "normal": normal, "point": origin + (o + d * t) * v}
		var axis := 2
		if t_next.x < t_next.y and t_next.x < t_next.z:
			axis = 0
		elif t_next.y < t_next.z:
			axis = 1
		cell[axis] += step[axis]
		t = t_next[axis]
		t_next[axis] += t_delta[axis]
		normal = Vector3.ZERO
		normal[axis] = -step[axis]
		if cell.x < 0 or cell.y < 0 or cell.z < 0 or cell.x >= n.x or cell.y >= n.y or cell.z >= n.z:
			break
	return {}


## A box covering the model: centred on x and z, standing on y = 0.
static func _box(extent: Vector3) -> ArrayMesh:
	var box := BoxMesh.new()
	box.size = extent
	var arrays := box.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in vertices.size():
		vertices[i].y += extent.y / 2.0
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out
