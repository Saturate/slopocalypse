shader_type spatial;
// Voxel ground: the colour each column was given, with a little per-voxel brightness
// variation so large plain areas don't look flat. The variation is computed here rather
// than baked into vertex colours, so equal neighbours still merge into big faces.

// The tile's voxel size, so the variation matches the blocks at every level of detail.
instance uniform float voxel = 0.25;
uniform float variation : hint_range(0.0, 0.5) = 0.07;
// Tilted tops (gentle slopes) vary more, so a smooth slope still reads as voxels.
uniform float tilt_variation : hint_range(0.0, 0.5) = 0.16;
// Painted ground (yards, lanes, a track's edge) takes the strip model's grain: its voxel
// size and its dirt's brightness jitter.
uniform float paint_grain = 0.1;
uniform float paint_jitter : hint_range(0.0, 0.5) = 0.14;
// How much of a wall's own colour shows when the sun is behind it.
uniform float wall_glow : hint_range(0.0, 0.5) = 0.12;

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
	// The mesher marks vertices in alpha: 1 plain, 0.75 painted by a way (a yard, a lane, a
	// track's edge), 0.25 a sloping tilted top, 0 both.
	bool sloping = COLOR.a < 0.5;
	bool painted = abs(COLOR.a - 0.75) < 0.1 || COLOR.a < 0.1;
	// Step half a voxel inward so a face picks the cell it belongs to, not its neighbour.
	float size = painted ? paint_grain : voxel;
	vec3 cell = floor((world_pos - world_normal * size * 0.5) / size);
	float amount = variation;
	// A sloping tilted top crosses layers: keyed by its column alone, or the variation would
	// change in stripes along its contour lines. Its fragments all lie inside the column.
	if (sloping) {
		cell = vec3(floor(world_pos.x / size), 0.0, floor(world_pos.z / size));
		amount = tilt_variation;
	}
	float n = hash(cell) - 0.5;
	// Colours are picked in sRGB.
	vec3 base = pow(COLOR.rgb, vec3(2.2));
	ALBEDO = base * (1.0 + n * 2.0 * amount);
	ROUGHNESS = 0.95;
	SPECULAR = 0.15;
	if (painted) {
		// As the track strip's dirt is drawn: the same cells, brightness jittered in sRGB,
		// and its material's roughness and specular.
		ALBEDO = pow(COLOR.rgb * (1.0 + n * 2.0 * paint_jitter), vec3(2.2));
		ROUGHNESS = 0.92;
		SPECULAR = 0.5;
	}
	// Walls facing away from the sun would be black: a little of their own colour shows.
	if (abs(world_normal.y) < 0.1) {
		EMISSION = ALBEDO * wall_glow;
	}
}
