class_name VoxelChunkedMesh
extends Node3D
## Draws a `VoxelModel` as one mesh per section of chunks of 16 cells, 4 x 4 x 4 chunks
## (9.6 m at 0.15 m voxels) unless told otherwise, so a building is a handful of mesh
## instances rather than hundreds: each instance is a draw call per pass, and a city of them
## was fifteen thousand. Models that get shot at (`editable`, set before the model) use
## `sections.editable_chunks` from voxkit.json (1: a chunk each, as cheap per bullet hole as
## meshing one chunk), because an edit re-joins its whole section. Once a section is edited the model keeps its
## chunks' meshes, so later edits mesh only the chunks they touch; sections never edited keep
## nothing. Call `refresh()` after editing; it replaces just the changed sections. One mesh
## instance per section rather than one surface per section, because an `ArrayMesh` surface
## cannot be replaced on its own.

const CONFIG := "res://modules/voxkit/data/voxkit.json"
## Editable section size when the data leaves it out.
const FALLBACK_EDITABLE_CHUNKS := 1

var model: VoxelModel:
	set(value):
		model = value
		_clear()
		_sized = false
## True for a model that gets shot at or broken: drawn in smaller sections.
var editable := false

static var _editable_chunks := -1
## True when the model draws some materials see-through (`VoxelModel.set_clear_materials`):
## each section then has a second, see-through mesh for them.
var layered := false

## The look of see-through voxels (glass): their own colour, mostly transparent, a little shine.
static var _glass: StandardMaterial3D

## Whether the section size has been set on the model yet.
var _sized := false
## Section id -> its mesh instance (sections with nothing to draw have none).
var _parts: Dictionary[int, MeshInstance3D] = {}
## Section id -> its see-through mesh instance.
var _clear_parts: Dictionary[int, MeshInstance3D] = {}


## Rebuilds the sections changed since the last refresh. Returns how many it rebuilt.
func refresh() -> int:
	if model == null:
		return 0
	VoxShading.ensure()
	if editable and not _sized:
		model.set_section_chunks(editable_chunks())
	_sized = true
	var t := Prof.start()
	var rebuilt: Dictionary = model.remesh_dirty_sections()
	for key: Variant in rebuilt:
		var id := int(key)
		var pair: Array = rebuilt[key]
		_show(_parts, id, pair[0], VoxGenerator.material(), "Section%d" % id)
		if layered:
			_show(_clear_parts, id, pair[1], glass_material(), "Glass%d" % id)
	Prof.stop(&"voxkit/remesh", t)
	return rebuilt.size()


## Section side in chunks for models that get edited (voxkit.json `sections.editable_chunks`).
static func editable_chunks() -> int:
	if _editable_chunks < 0:
		_editable_chunks = FALLBACK_EDITABLE_CHUNKS
		var data: Variant = Data.load_json(CONFIG)
		var sections: Variant = (data as Dictionary).get("sections") if data is Dictionary else null
		if sections is Dictionary and Data.require(CONFIG + " sections", sections, {"editable_chunks": TYPE_FLOAT}):
			_editable_chunks = maxi(1, int((sections as Dictionary)["editable_chunks"]))
	return _editable_chunks


## Puts `arrays` on section `id`'s instance in `parts` (making it), or frees it when empty.
func _show(parts: Dictionary[int, MeshInstance3D], id: int, arrays: Array, material: Material, part_name: String) -> void:
	if arrays.is_empty():
		if parts.has(id):
			parts[id].queue_free()
			parts.erase(id)
		return
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	if not parts.has(id):
		var part := MeshInstance3D.new()
		part.name = part_name
		add_child(part)
		parts[id] = part
	parts[id].mesh = mesh


## The see-through look: the voxels' own colour at about a third, with some shine, both sides.
static func glass_material() -> StandardMaterial3D:
	if _glass == null:
		_glass = StandardMaterial3D.new()
		_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glass.vertex_color_use_as_albedo = true
		_glass.vertex_color_is_srgb = true
		_glass.albedo_color = Color(1.0, 1.0, 1.0, 0.32)
		_glass.metallic = 0.1
		_glass.roughness = 0.08
		_glass.metallic_specular = 0.8
		_glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _glass


## The see-through section meshes drawn now, for tests and tools.
func clear_meshes() -> Array[Mesh]:
	var out: Array[Mesh] = []
	for part: MeshInstance3D in _clear_parts.values():
		out.append(part.mesh)
	return out


## The section meshes drawn now, for tests and tools.
func chunk_meshes() -> Array[Mesh]:
	var out: Array[Mesh] = []
	for part: MeshInstance3D in _parts.values():
		out.append(part.mesh)
	return out


## How many mesh instances this model is drawn with (both layers).
func part_count() -> int:
	return _parts.size() + _clear_parts.size()


func _clear() -> void:
	for part: MeshInstance3D in _parts.values():
		part.queue_free()
	_parts.clear()
	for part: MeshInstance3D in _clear_parts.values():
		part.queue_free()
	_clear_parts.clear()
