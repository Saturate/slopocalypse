shader_type spatial;
// Voxel terrain colour from the surface itself: grass on gentle ground, dirt on slopes,
// rock on steep faces and in dug craters, mottled by world-space noise. No textures yet;
// the art pass (#38) swaps the flat colours for triplanar CC0 textures.

uniform vec3 grass_a : source_color = vec3(0.24, 0.36, 0.17);
uniform vec3 grass_b : source_color = vec3(0.40, 0.46, 0.24);
uniform vec3 dirt : source_color = vec3(0.42, 0.33, 0.22);
uniform vec3 rock : source_color = vec3(0.40, 0.39, 0.37);
uniform float dirt_start = 0.82;
uniform float rock_start = 0.62;

varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float up = world_normal.y;
	float broad = noise(world_pos.xz * 0.04);
	float fine = noise(world_pos.xz * 0.6);
	vec3 grass = mix(grass_a, grass_b, broad) * mix(0.9, 1.08, fine);
	vec3 c = mix(dirt * mix(0.9, 1.1, fine), grass, smoothstep(dirt_start - 0.06, dirt_start + 0.06, up));
	c = mix(rock * mix(0.85, 1.1, fine), c, smoothstep(rock_start - 0.06, rock_start + 0.06, up));
	ALBEDO = c;
	ROUGHNESS = 0.95;
}
