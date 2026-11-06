shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
// Conifer branch cards: alpha cut-out needles, tinted per tree instance, swaying with the
// wind more toward branch tips and the crown.
//
// Normals are authored pointing out from the trunk (a soft "spherised" crown) and the back
// face uses the same normal as the front, so cards light as one volume instead of turning
// black when seen from behind.

uniform sampler2D needles : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float alpha_cut = 0.45;
uniform float sway = 0.08;
uniform float speed = 0.9;
uniform float translucency = 0.35;

varying vec3 tint;
varying float tip;

void vertex() {
	// UV.x runs from trunk (0) to branch tip (1); tips and higher branches sway more.
	tip = UV.x;
	vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float t = TIME * speed + root.x * 0.13 + root.z * 0.11;
	float amount = sway * tip * (0.4 + VERTEX.y * 0.08);
	VERTEX.x += sin(t + VERTEX.y * 0.4) * amount;
	VERTEX.z += cos(t * 0.8 + VERTEX.y * 0.3) * amount * 0.7;
	VERTEX.y += sin(t * 1.7 + UV.x * 3.0) * amount * 0.3;
	tint = COLOR.rgb;
}

void fragment() {
	vec4 tex = texture(needles, UV);
	if (tex.a < alpha_cut) {
		discard;
	}
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	// Inner needles near the trunk are in their own shade.
	ALBEDO = tex.rgb * tint * mix(0.55, 1.0, tip);
	ROUGHNESS = 0.85;
	SPECULAR = 0.15;
	BACKLIGHT = vec3(translucency) * tex.rgb;
}
