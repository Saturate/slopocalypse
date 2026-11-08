shader_type spatial;
// Pixel-art pass over the 3D view: the viewport already renders at a fraction of the window
// and is scaled up with nearest filtering; this adds dark outlines where depth jumps,
// light rims on convex edges (normal changes) and a limited number of colour levels.
render_mode unshaded, fog_disabled, depth_draw_never, cull_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest;
uniform bool outlines = true;
uniform float outline_strength : hint_range(0.0, 1.0) = 0.55;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.25;
uniform float levels : hint_range(2.0, 64.0) = 14.0;
// A depth jump counts as an edge when it is this share of the distance.
uniform float depth_edge = 0.03;
uniform float dither : hint_range(0.0, 1.0) = 0.45;
const float BAYER[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float view_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).x;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -v.z / v.w;
}

vec3 view_normal(vec2 uv) {
	return texture(normal_tex, uv).xyz * 2.0 - 1.0;
}

void fragment() {
	vec2 px = 1.0 / VIEWPORT_SIZE;
	vec3 colour = texture(screen_tex, SCREEN_UV).rgb;
	if (outlines) {
		float d = view_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
		vec3 n = view_normal(SCREEN_UV);
		float edge = 0.0;
		float rim = 0.0;
		vec2 dirs[4] = vec2[](vec2(1.0, 0.0), vec2(-1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, -1.0));
		for (int i = 0; i < 4; i++) {
			vec2 uv = SCREEN_UV + dirs[i] * px;
			float dn = view_depth(uv, INV_PROJECTION_MATRIX);
			// Only the nearer side of a depth jump draws the line, so it stays one pixel.
			if (dn - d > d * depth_edge) {
				edge = 1.0;
			}
			if (abs(dn - d) < d * depth_edge && dot(n, view_normal(uv)) < 0.7) {
				rim = 1.0;
			}
		}
		colour *= 1.0 - edge * outline_strength;
		colour *= 1.0 + rim * (1.0 - edge) * rim_strength;
	}
	// Levels are cut in sRGB, where steps are even to the eye; in linear light the darks
	// all collapse into the first step and shadows turn black or tinted.
	vec3 srgb = pow(max(colour, vec3(0.0)), vec3(1.0 / 2.2));
	// The sky has no depth; a dither pattern across it only reads as noise.
	float sky = step(0.999999, 1.0 - texture(depth_tex, SCREEN_UV).x);
	// Ordered (Bayer) dither so smooth gradients like fog break into a pixel pattern
	// instead of hard rings.
	ivec2 cell = ivec2(FRAGCOORD.xy) % 4;
	float bayer = BAYER[cell.y * 4 + cell.x] / 16.0 - 0.5;
	srgb = floor(srgb * levels + 0.5 + bayer * dither * (1.0 - sky)) / levels;
	ALBEDO = pow(srgb, vec3(2.2));
}
