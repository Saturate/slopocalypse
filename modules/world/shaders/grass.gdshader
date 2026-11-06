shader_type spatial;
// Grass tufts: sway in a slow travelling wind (stronger toward the tips), darker at the base
// for cheap contact shading. Colour comes from the MultiMesh instance colour, picked in sRGB.

uniform float sway = 0.07;
uniform float speed = 1.4;
uniform float blade_height = 0.35;

varying float height01;
varying vec3 tint;

void vertex() {
	height01 = clamp(VERTEX.y / blade_height, 0.0, 1.0);
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float t = TIME * speed + wp.x * 0.3 + wp.z * 0.2;
	float bend = height01 * height01;
	VERTEX.x += (sin(t) + 0.4 * sin(t * 2.3)) * sway * bend;
	VERTEX.z += cos(t * 0.8) * sway * 0.6 * bend;
	tint = COLOR.rgb;
}

void fragment() {
	// Instance colours are authored in sRGB.
	vec3 c = pow(tint, vec3(2.2));
	ALBEDO = c * mix(0.45, 1.0, height01);
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
}
