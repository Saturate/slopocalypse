class_name VoxelVolume
extends MeshInstance3D
## Draws a `VoxelModel` on the GPU instead of as a mesh (#306): its cells go into a 3D
## texture and `voxel_volume.gdshader` finds the first filled cell along each pixel's ray, so
## the cost follows screen pixels, not the number of voxels or faces. The node's origin is the
## model's origin (x and z centred, y from the ground), like a mesh of the same model.
## Client only.

const SHADER := preload("res://modules/voxkit/shaders/voxel_volume.gdshader")
## Cells per side of the empty-space bricks; the shader's BRICK must match.
const BRICK := 4

var model: VoxelModel

var _texture: ImageTexture3D
var _bricks: ImageTexture3D
var _material: ShaderMaterial


## Uploads the model's cells and sizes the box to it; call after building or editing it.
func refresh() -> void:
	var t := Prof.start()
	var n := model.cells()
	var v := model.voxel_size()
	if n.x * n.y * n.z == 0:
		mesh = null
		return
	var bytes := model.rgba_slices()
	var layer := n.x * n.y * 4
	var images: Array[Image] = []
	for z in n.z:
		images.append(Image.create_from_data(n.x, n.y, false, Image.FORMAT_RGBA8, bytes.slice(z * layer, (z + 1) * layer)))
	if _texture == null:
		_texture = ImageTexture3D.new()
	_texture.create(Image.FORMAT_RGBA8, n.x, n.y, n.z, false, images)
	var extent := Vector3(n) * v
	mesh = _box(extent)
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	_bricks = _occupancy_texture(model, _bricks)
	_material.set_shader_parameter("cells", _texture)
	_material.set_shader_parameter("bricks", _bricks)
	_material.set_shader_parameter("size", n)
	_material.set_shader_parameter("voxel", v)
	_material.set_shader_parameter("origin", Vector3(-extent.x / 2.0, 0.0, -extent.z / 2.0))
	VoxShading.ensure()
	var levels := VoxShading.levels
	_material.set_shader_parameter("corner_levels", Vector4(levels[0], levels[1], levels[2], levels[3]) if levels.size() == 4 else Vector4.ONE)
	material_override = _material
	Prof.stop(&"voxkit/volume_upload", t)


static func _occupancy_texture(m: VoxelModel, into: ImageTexture3D) -> ImageTexture3D:
	var counts := m.brick_counts(BRICK)
	var bytes := m.brick_occupancy(BRICK)
	var layer := counts.x * counts.y
	var images: Array[Image] = []
	for z in counts.z:
		images.append(Image.create_from_data(counts.x, counts.y, false, Image.FORMAT_R8, bytes.slice(z * layer, (z + 1) * layer)))
	var out := into if into != null else ImageTexture3D.new()
	out.create(Image.FORMAT_R8, counts.x, counts.y, counts.z, false, images)
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
