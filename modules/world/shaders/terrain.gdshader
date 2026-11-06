shader_type spatial;
// Voxel terrain: triplanar CC0 PBR textures (no UVs on voxel meshes, and crater walls are
// vertical), blended grass -> dirt -> rock by slope with noise breakup, tinted toward a
// grounded, muted palette. Grass only uses the top-down projection; dirt and rock use all
// three so cliffs and crater walls don't stretch.

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

uniform float grass_scale = 0.33;
uniform float dirt_scale = 0.25;
uniform float rock_scale = 0.15;
uniform vec3 grass_tint : source_color = vec3(0.66, 0.66, 0.42);
uniform vec3 dirt_tint : source_color = vec3(0.62, 0.56, 0.5);
uniform vec3 rock_tint : source_color = vec3(0.62, 0.62, 0.6);
uniform float dirt_start = 0.86;
uniform float rock_start = 0.6;
uniform float normal_strength = 0.9;
// Baked by Biomes: R forest, G dry, B rock, covering the whole world.
uniform sampler2D biome_map : hint_default_black, filter_linear, repeat_disable;
uniform float world_size = 256.0;

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

// Tangent-space normal map sample turned into a world-space offset for one projection plane.
vec3 unpack(vec3 n) {
	return vec3(n.xy * 2.0 - 1.0, 1.0) * vec3(normal_strength, normal_strength, 1.0);
}

struct Surface {
	vec3 albedo;
	float rough;
	vec3 normal;
};

// Full triplanar: three projections weighted by the surface normal ("whiteout" normal blend).
Surface triplanar(sampler2D alb, sampler2D nrm, sampler2D rgh, float scale, vec3 w) {
	vec3 p = world_pos * scale;
	vec3 an = abs(world_normal);
	vec3 b = pow(an, vec3(6.0));
	b /= (b.x + b.y + b.z);
	Surface s;
	s.albedo = texture(alb, p.zy).rgb * b.x + texture(alb, p.xz).rgb * b.y + texture(alb, p.xy).rgb * b.z;
	s.rough = texture(rgh, p.zy).r * b.x + texture(rgh, p.xz).r * b.y + texture(rgh, p.xy).r * b.z;
	vec3 tx = unpack(texture(nrm, p.zy).rgb);
	vec3 ty = unpack(texture(nrm, p.xz).rgb);
	vec3 tz = unpack(texture(nrm, p.xy).rgb);
	vec3 nx = vec3(0.0, tx.y, tx.x) * sign(world_normal.x);
	vec3 ny = vec3(ty.x, 0.0, ty.y) * sign(world_normal.y);
	vec3 nz = vec3(tz.x, tz.y, 0.0) * sign(world_normal.z);
	s.normal = normalize(world_normal + nx * b.x + ny * b.y + nz * b.z);
	return s;
}

// Top-down only, for grass, which only grows on gentle ground.
Surface top(sampler2D alb, sampler2D nrm, sampler2D rgh, float scale) {
	vec2 p = world_pos.xz * scale;
	Surface s;
	s.albedo = texture(alb, p).rgb;
	s.rough = texture(rgh, p).r;
	vec3 t = unpack(texture(nrm, p).rgb);
	s.normal = normalize(world_normal + vec3(t.x, 0.0, t.y));
	return s;
}

void fragment() {
	vec3 biome = texture(biome_map, world_pos.xz / world_size + 0.5).rgb;
	float forest = biome.r;
	float rocky = biome.b;
	float breakup = noise(world_pos.xz * 0.15) * 0.12 + noise(world_pos.xz * 0.9) * 0.05;
	float up = world_normal.y + breakup - 0.08;
	// Rocky ground shows rock even where it's fairly flat; forest floors show more soil.
	float rock_line = rock_start + rocky * 0.3;
	float dirt_line = dirt_start + rocky * 0.08 + forest * 0.04;
	float w_grass = smoothstep(dirt_line - 0.05, dirt_line + 0.05, up);
	float w_rock = 1.0 - smoothstep(rock_line - 0.06, rock_line + 0.06, up);
	float w_dirt = clamp(1.0 - w_grass - w_rock, 0.0, 1.0);

	Surface g = top(grass_albedo, grass_normal, grass_rough, grass_scale);
	Surface d = triplanar(dirt_albedo, dirt_normal, dirt_rough, dirt_scale, world_normal);
	Surface r = triplanar(rock_albedo, rock_normal, rock_rough, rock_scale, world_normal);

	// Large-scale tone variation so open fields don't read as one repeated tile, plus patches
	// of dry, khaki grass for a lived-in, less lawn-like look.
	float tone = mix(0.82, 1.08, noise(world_pos.xz * 0.03));
	float dry = biome.g;
	vec3 grass_col = mix(g.albedo * grass_tint, g.albedo * vec3(0.86, 0.76, 0.46), dry * 0.8);
	// Forest floor: shaded, brown needle litter showing through thin grass.
	vec3 litter = mix(g.albedo * grass_tint * 0.6, d.albedo * vec3(0.5, 0.38, 0.26), 0.55);
	grass_col = mix(grass_col, litter, forest * 0.85);
	vec3 albedo = (grass_col * w_grass + d.albedo * dirt_tint * w_dirt + r.albedo * rock_tint * w_rock) * tone;
	vec3 n = normalize(g.normal * w_grass + d.normal * w_dirt + r.normal * w_rock);
	ALBEDO = albedo;
	ROUGHNESS = g.rough * w_grass + d.rough * w_dirt + r.rough * w_rock;
	// Grass reflecting the blue sky at grazing angles gave fields a cold sheen; real grass
	// barely does. Bare dirt and rock keep a little.
	SPECULAR = 0.12 * w_grass + 0.35 * (w_dirt + w_rock);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
