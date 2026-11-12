// A voxel model drawn without a mesh (#306): the model's cells are in 3D textures, and each
// pixel of the model's bounding box walks its view ray through the grid one cell at a time
// (a 3D DDA) until it finds a filled cell. It writes that cell's colour, the normal of the
// face the ray came in through, and the depth of the hit, so the model sorts against meshes
// and casts and receives shadows like any opaque surface.
shader_type spatial;
// The inside of the box is drawn so the model still shows with the camera inside it (in a
// building); the ray starts at the camera then.
render_mode cull_front;

// Only the BRICK-cell cubes that hold anything are stored, packed side by side in `atlas`
// (two bytes a cell: the sRGB colour as 5-6-5 bits, 0 for air). `indirection` has a texel
// per brick of the model: where that brick sits in the atlas, in bricks (red, green, blue
// times 255), with alpha 0 for an empty brick, which the walk jumps over whole. Both are read
// with texelFetch, never filtered.
uniform sampler3D indirection : filter_nearest, repeat_disable;
uniform sampler3D atlas : filter_nearest, repeat_disable;
const int BRICK = 4;
// Cells per axis, metres per cell, and where cell (0, 0, 0)'s corner sits in the node.
uniform ivec3 size;
uniform float voxel;
uniform vec3 origin;
uniform float roughness = 0.92;
// Brightness of a face corner by how many cells crowd it, from 0 (tucked into an inside
// corner) to 3 (open): the same corner shading the meshes bake in (all 1 for none).
uniform vec4 corner_levels = vec4(1.0);

// A cell's 5-6-5 colour bits from its brick's place in the atlas (0 for air).
uint cell_bits(ivec3 c, vec4 place) {
	ivec3 at = ivec3(round(place.rgb * 255.0)) * BRICK + c % BRICK;
	vec2 bytes = round(texelFetch(atlas, at, 0).rg * 255.0);
	return uint(bytes.x) | (uint(bytes.y) << 8u);
}

vec3 linear_colour(uint bits) {
	vec3 c = vec3(float((bits >> 11u) & 31u) / 31.0, float((bits >> 5u) & 63u) / 63.0, float(bits & 31u) / 31.0);
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

float filled(ivec3 c) {
	if (any(lessThan(c, ivec3(0))) || any(greaterThanEqual(c, size))) {
		return 0.0;
	}
	vec4 place = texelFetch(indirection, c / BRICK, 0);
	if (place.a < 0.5) {
		return 0.0;
	}
	return cell_bits(c, place) != 0u ? 1.0 : 0.0;
}

// The same rule as `voxkit_core::corner_level`.
float corner(float side_a, float side_b, float diagonal) {
	int level = side_a > 0.5 && side_b > 0.5 ? 0 : 3 - int(side_a + side_b + diagonal);
	return corner_levels[level];
}

void fragment() {
	// The pixel's ray in view space: from the eye for a perspective camera, straight ahead
	// for an orthographic one (directional light shadows).
	bool ortho = PROJECTION_MATRIX[3][3] != 0.0;
	vec3 ray_origin = ortho ? vec3(VERTEX.xy, 0.0) : vec3(0.0);
	vec3 ray_dir = ortho ? vec3(0.0, 0.0, -1.0) : normalize(VERTEX);
	mat4 to_local = inverse(MODEL_MATRIX) * INV_VIEW_MATRIX;
	// Into grid units, where a cell is 1 across.
	vec3 o = ((to_local * vec4(ray_origin, 1.0)).xyz - origin) / voxel;
	vec3 d = normalize((to_local * vec4(ray_dir, 0.0)).xyz);
	d += vec3(equal(d, vec3(0.0))) * 1e-6;
	vec3 inv = 1.0 / d;
	vec3 grid = vec3(size);
	vec3 t_low = -o * inv;
	vec3 t_high = (grid - o) * inv;
	vec3 t_near = min(t_low, t_high);
	vec3 t_far = max(t_low, t_high);
	float enter = max(max(t_near.x, t_near.y), t_near.z);
	float leave = min(min(t_far.x, t_far.y), t_far.z);
	if (leave < max(enter, 0.0)) {
		discard;
	}
	float t = max(enter, 0.0);
	ivec3 step_dir = ivec3(sign(d));
	vec3 t_delta = abs(inv);
	ivec3 cell = clamp(ivec3(floor(o + d * (t + 1e-4))), ivec3(0), size - 1);
	// When the next cell boundary along each axis comes.
	vec3 t_next = (vec3(cell) + max(vec3(step_dir), vec3(0.0)) - o) * inv;
	// The face the ray came in through: the box face it entered by, until it steps.
	vec3 normal = -vec3(step_dir) * vec3(equal(t_near, vec3(enter)));
	if (enter < 0.0) {
		normal = -d;
	}
	uint hit = 0u;
	int steps = size.x + size.y + size.z;
	for (int i = 0; i < steps; i++) {
		ivec3 brick = cell / BRICK;
		vec4 place = texelFetch(indirection, brick, 0);
		if (place.a < 0.5) {
			// Out of this brick in one go: to the first of its faces the ray crosses.
			vec3 low = vec3(brick * BRICK);
			vec3 bound = low + vec3(greaterThan(d, vec3(0.0))) * float(BRICK);
			vec3 t_out = (bound - o) * inv;
			int axis = t_out.x <= t_out.y && t_out.x <= t_out.z ? 0 : (t_out.y <= t_out.z ? 1 : 2);
			t = t_out[axis];
			cell = ivec3(floor(o + d * t));
			cell[axis] = step_dir[axis] > 0 ? int(bound[axis]) : int(low[axis]) - 1;
			t_next = (vec3(cell) + max(vec3(step_dir), vec3(0.0)) - o) * inv;
			normal = vec3(0.0);
			normal[axis] = -float(step_dir[axis]);
			if (any(lessThan(cell, ivec3(0))) || any(greaterThanEqual(cell, size))) {
				break;
			}
			continue;
		}
		uint bits = cell_bits(cell, place);
		if (bits != 0u) {
			hit = bits;
			break;
		}
		if (t_next.x < t_next.y && t_next.x < t_next.z) {
			cell.x += step_dir.x;
			t = t_next.x;
			t_next.x += t_delta.x;
			normal = vec3(-float(step_dir.x), 0.0, 0.0);
		} else if (t_next.y < t_next.z) {
			cell.y += step_dir.y;
			t = t_next.y;
			t_next.y += t_delta.y;
			normal = vec3(0.0, -float(step_dir.y), 0.0);
		} else {
			cell.z += step_dir.z;
			t = t_next.z;
			t_next.z += t_delta.z;
			normal = vec3(0.0, 0.0, -float(step_dir.z));
		}
		if (any(lessThan(cell, ivec3(0))) || any(greaterThanEqual(cell, size))) {
			break;
		}
	}
	if (hit == 0u) {
		discard;
	}
	// Corner shading across the face, from the cells around the air cell in front of it.
	ivec3 n = ivec3(normal);
	int axis = abs(n.x) > 0 ? 0 : (abs(n.y) > 0 ? 1 : 2);
	ivec3 u = axis == 0 ? ivec3(0, 1, 0) : ivec3(1, 0, 0);
	ivec3 v = axis == 2 ? ivec3(0, 1, 0) : ivec3(0, 0, 1);
	ivec3 front = cell + n;
	vec3 g = o + d * t;
	float fu = fract(dot(g, vec3(u)));
	float fv = fract(dot(g, vec3(v)));
	float su0 = filled(front - u);
	float su1 = filled(front + u);
	float sv0 = filled(front - v);
	float sv1 = filled(front + v);
	float c00 = corner(su0, sv0, filled(front - u - v));
	float c10 = corner(su1, sv0, filled(front + u - v));
	float c01 = corner(su0, sv1, filled(front - u + v));
	float c11 = corner(su1, sv1, filled(front + u + v));
	float shade = mix(mix(c00, c10, fu), mix(c01, c11, fu), fv);
	vec3 point = origin + (o + d * t) * voxel;
	vec3 view_point = (VIEW_MATRIX * MODEL_MATRIX * vec4(point, 1.0)).xyz;
	vec4 clip = PROJECTION_MATRIX * vec4(view_point, 1.0);
	// Kept in range: a directional light's shadow pass flattens casters in front of its near
	// plane onto it, and an unclamped depth there would drop them.
	DEPTH = clamp(clip.z / clip.w, 0.0, 1.0);
	// Light and shadows are worked out where the ray hit, not on the box face drawn.
	LIGHT_VERTEX = view_point;
	ALBEDO = linear_colour(hit) * shade;
	NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(normal, 0.0)).xyz);
	ROUGHNESS = roughness;
}
