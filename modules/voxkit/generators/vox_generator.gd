class_name VoxGenerator
extends RefCounted
## A voxel model made by code. Each generator lists its parameters (the asset library turns
## them into sliders) and builds a VoxelModel from a set of values. Shapes are described in
## metres, so the voxel size is just another parameter: a gun wants centimetres, a wall a
## decimetre.
##
## A parameter is `{key, label, min, max, step, default}`; `step` 1 makes it whole numbers,
## and `options` (a list of labels) makes it a choice whose value is the index.

static var _material: StandardMaterial3D


func title() -> String:
	return ""


func params() -> Array[Dictionary]:
	return []


func build(_p: Dictionary) -> VoxelModel:
	return null


func defaults() -> Dictionary:
	var out := {}
	for p in params():
		out[p["key"]] = p["default"]
	return out


## `params()` values filled in from `p` where given, defaults elsewhere.
func with_defaults(p: Dictionary) -> Dictionary:
	var out := defaults()
	out.merge(p, true)
	return out


static func param(key: String, label: String, lo: float, hi: float, step: float, value: float) -> Dictionary:
	return {"key": key, "label": label, "min": lo, "max": hi, "step": step, "default": value}


static func choice(key: String, label: String, options: Array[String], value: int) -> Dictionary:
	return {"key": key, "label": label, "min": 0.0, "max": float(options.size() - 1), "step": 1.0, "default": float(value), "options": options}


static func seed_param(value: int = 1) -> Dictionary:
	return param("seed", "Seed", 0.0, 9999.0, 1.0, float(value))


static func voxel_param(lo: float, hi: float, value: float) -> Dictionary:
	return param("voxel", "Voxel size (m)", lo, hi, 0.005, value)


## The model as a mesh with the shared vertex-colour material, or an empty mesh.
static func to_mesh(model: VoxelModel) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if model == null:
		return mesh
	var arrays := model.mesh_arrays()
	if arrays.is_empty():
		return mesh
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material())
	return mesh


static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		# Colours are picked in sRGB; Godot reads vertex colours as linear by default.
		_material.vertex_color_is_srgb = true
		_material.roughness = 0.92
	return _material
