shader_type spatial;
// Voxel ground: the colour each column was given, with a little per-voxel brightness
// variation so large plain areas don't look flat. The variation is computed here rather
// than baked into vertex colours, so equal neighbours still merge into big faces.

// The tile's voxel size, so the variation matches the blocks at every level of detail.
instance uniform float voxel = 0.25;
uniform float variation : hint_range(0.0, 0.5) = 0.07;

varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = NORMAL;
}

void fragment() {
	// Step half a voxel inward so a face picks the cell it belongs to, not its neighbour.
	vec3 cell = floor((world_pos - world_normal * voxel * 0.5) / voxel);
	float n = hash(cell) - 0.5;
	// Colours are picked in sRGB.
	vec3 base = pow(COLOR.rgb, vec3(2.2));
	ALBEDO = base * (1.0 + n * 2.0 * variation);
	ROUGHNESS = 0.95;
	SPECULAR = 0.15;
}
