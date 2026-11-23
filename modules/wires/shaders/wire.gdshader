shader_type spatial;
// Wires: vertices sit on the wire's surface with NORMAL pointing out from its middle and
// UV.x holding its radius. Far away a wire would be thinner than a pixel and break up into
// dashes, so it is pushed out to `min_pixels` wide on screen. UV.x of 0 (barbs) is never
// widened.

uniform float min_pixels = 1.0;
uniform float roughness = 0.55;
// Faces round the wire: seen square to a face it looks cos(PI / sides) as wide as across
// its corners, so the kept width is divided by that to meet min_pixels from every side.
uniform float sides = 4.0;

void vertex() {
	if (UV.x > 0.0) {
		// An orthographic camera (map overview, item icons) draws everything at one scale:
		// a pixel is the same size at any distance, so distance must not widen the wire.
		bool ortho = PROJECTION_MATRIX[3][3] == 1.0;
		float distance = ortho ? 1.0 : length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
		// One pixel at that distance is 2d / (|P11| · height) across (2 / (|P11| · height)
		// in orthographic); half of min_pixels of them is the radius to keep. P11 is negative
		// where the renderer flips Y.
		float keep = min_pixels * distance / (abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y);
		keep /= cos(PI / sides);
		VERTEX += NORMAL * max(0.0, keep - UV.x);
	}
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = roughness;
}
