class_name VoxelChunkedMesh
extends Node3D
## Draws a `VoxelModel` as one mesh per 16-cell chunk, so an edit (a bullet hole, a broken
## wall piece) rebuilds only the chunks it touched instead of the whole model. Call
## `refresh()` after editing; it replaces just the changed chunks. One mesh instance per
## chunk rather than one surface per chunk, because an `ArrayMesh` surface cannot be replaced
## on its own.

var model: VoxelModel:
	set(value):
		model = value
		_clear()

## Chunk id -> its mesh instance (chunks with nothing to draw have none).
var _parts: Dictionary[int, MeshInstance3D] = {}


## Rebuilds the chunks changed since the last refresh. Returns how many it rebuilt.
func refresh() -> int:
	if model == null:
		return 0
	VoxShading.ensure()
	var t := Prof.start()
	var rebuilt: Dictionary = model.remesh_dirty()
	for key: Variant in rebuilt:
		var id := int(key)
		var arrays: Array = rebuilt[key]
		if arrays.is_empty():
			if _parts.has(id):
				_parts[id].queue_free()
				_parts.erase(id)
			continue
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, VoxGenerator.material())
		if not _parts.has(id):
			var part := MeshInstance3D.new()
			part.name = "Chunk%d" % id
			add_child(part)
			_parts[id] = part
		_parts[id].mesh = mesh
	Prof.stop(&"voxkit/remesh", t)
	return rebuilt.size()


## The chunk meshes drawn now, for tests and tools.
func chunk_meshes() -> Array[Mesh]:
	var out: Array[Mesh] = []
	for part: MeshInstance3D in _parts.values():
		out.append(part.mesh)
	return out


func _clear() -> void:
	for part: MeshInstance3D in _parts.values():
		part.queue_free()
	_parts.clear()
