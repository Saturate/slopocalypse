shader_type spatial;
// The scope's eyepiece: the magnified picture from the scope camera, a reticle (fine cross
// with heavy outer posts, as on a hunting duplex), and a dark rim. Below `active` it is
// dark glass.
render_mode unshaded, shadows_disabled, cull_back;

uniform sampler2D view : source_color, filter_linear;
uniform float active = 0.0;

const float LINE = 0.007;
const float POST = 0.055;
const float POST_FROM = 0.38;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	vec3 world = texture(view, UV).rgb;
	float fine = step(abs(p.x), LINE) + step(abs(p.y), LINE);
	float posts = step(abs(p.x), POST) * step(POST_FROM, abs(p.y)) + step(abs(p.y), POST) * step(POST_FROM, abs(p.x));
	float ink = clamp(fine + posts, 0.0, 1.0);
	vec3 col = mix(world, vec3(0.0), ink);
	// The rim darkens like a real eyepiece's exit pupil edge.
	col *= 1.0 - smoothstep(0.88, 1.0, r);
	vec3 glass = vec3(0.015, 0.02, 0.025) + vec3(0.05) * smoothstep(0.4, 0.0, length(p - vec2(-0.35, 0.35)));
	ALBEDO = mix(glass, col, active);
}
