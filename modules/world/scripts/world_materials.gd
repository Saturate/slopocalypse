class_name WorldMaterials
extends RefCounted
## Textured materials for props, from the CC0 sets in modules/world/textures/. World-space
## triplanar mapping, so boxes and rocks of any size need no UVs and never stretch. No
## autoloads used: builders call this too.

const TEXTURES := "res://modules/world/textures/%s/%s_1K-JPG_"


## `metres_per_tile`: how much world space one repeat of the texture covers.
static func triplanar(set_name: String, tint: Color, metres_per_tile: float, use_instance_colour: bool = false) -> StandardMaterial3D:
	var base := TEXTURES % [set_name, set_name]
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(base + "Color.jpg")
	mat.normal_enabled = true
	mat.normal_texture = load(base + "NormalGL.jpg")
	mat.roughness_texture = load(base + "Roughness.jpg")
	mat.albedo_color = tint
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE / metres_per_tile
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if use_instance_colour:
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = true
	return mat
