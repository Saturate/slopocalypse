class_name WaterView
extends Node3D
## Client: one flat surface per pond at its level, shaded by how much water is under each
## spot (shallow tint at the edge to deep tint `colour_depth` metres down), with what is
## under the surface showing through, wobbled on a 0.25 m grid so it stays blocky like the
## ground.

const SHADER := """
shader_type spatial;
// Drawn after the opaque pass (ALPHA is set), so the screen and depth textures hold the
// ground under it.
render_mode cull_disabled, depth_draw_always;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform vec3 shallow : source_color = vec3(0.32, 0.5, 0.45);
uniform vec3 deep : source_color = vec3(0.05, 0.16, 0.2);
uniform float colour_depth = 3.0;
uniform float cell = 0.25;
varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 snapped = floor(world.xz / cell);
	float t = floor(TIME * 3.0);
	vec2 wobble = (vec2(hash(snapped + t), hash(snapped.yx - t)) - 0.5) * 0.006;
	vec2 uv = SCREEN_UV + wobble;
	float d = texture(depth_tex, uv).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(uv * 2.0 - 1.0, d, 1.0);
	view.xyz /= view.w;
	// How much water the eye looks through to reach what is behind the surface here.
	float through = max(length(view.xyz) - length(VERTEX), 0.0);
	if (-view.z < -VERTEX.z) {
		// Something in front of the water: don't refract it in.
		uv = SCREEN_UV;
		through = 0.0;
	}
	float k = clamp(through / colour_depth, 0.0, 1.0);
	vec3 behind = texture(screen, uv).rgb;
	vec3 tint = mix(shallow, deep, k);
	// What is under the water was lit already: it shows through as emission, fading with depth,
	// so it isn't lit twice; the water's own tint takes the light.
	ALBEDO = tint * (0.35 + 0.65 * k);
	EMISSION = behind * shallow * 1.4 * (1.0 - k);
	// Each 0.25 m cell tilts a little and changes a few times a second: blocky glints that
	// match the ground, not a smooth mirror.
	// Looking across the water at a low angle the glints and the sky's reflection would wash it
	// to white, so both fade as the view flattens.
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	vec3 tilt = vec3(hash(snapped + t * 1.7) - 0.5, 0.0, hash(snapped.yx + t * 2.3) - 0.5) * 0.06 * mix(0.12, 1.0, facing * facing);
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(tilt, 0.0)).xyz);
	ROUGHNESS = mix(0.18, 0.08, facing);
	SPECULAR = mix(0.32, 0.5, facing);
	METALLIC = 0.0;
	ALPHA = 1.0;
}
"""

var water: WaterBodies
## The `water` block of world.json.
var config: Dictionary = {}


func _ready() -> void:
	var shader := Shader.new()
	shader.code = SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter(&"shallow", _colour(config.get("shallow", [0.32, 0.5, 0.45])))
	material.set_shader_parameter(&"deep", _colour(config.get("deep", [0.05, 0.16, 0.2])))
	material.set_shader_parameter(&"colour_depth", float(config.get("colour_depth", 3.0)))
	for i in water.bodies.size():
		var mesh := surface_mesh(water.bodies[i]["outline"], water.level_of(i))
		if mesh == null:
			continue
		mesh.surface_set_material(0, material)
		var part := MeshInstance3D.new()
		part.name = "Body%d" % i
		part.mesh = mesh
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(part)


static func _colour(rgb: Array) -> Color:
	return Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))


## The outline filled in, flat at `level`, facing up; null if it can't be filled.
static func surface_mesh(outline: PackedVector2Array, level: float) -> ArrayMesh:
	var triangles := Geometry2D.triangulate_polygon(outline)
	if triangles.is_empty():
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	# Wound so the faces look up.
	var clockwise := Geometry2D.is_polygon_clockwise(outline)
	for t in range(0, triangles.size(), 3):
		var order := [0, 2, 1] if clockwise else [0, 1, 2]
		for o: int in order:
			var p := outline[triangles[t + o]]
			st.add_vertex(Vector3(p.x, level, p.y))
	return st.commit()
