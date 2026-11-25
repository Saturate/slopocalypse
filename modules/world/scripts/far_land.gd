class_name FarLand
extends MeshInstance3D
## Client: the whole map's land as one coarse mesh, drawn only past where the voxel ground is
## built round the camera (#454). Without it, looking out from high ground shows nothing
## past the load distance but the sky's floor; on an island that reads as a brown slab where
## the coast should be. A grid every `step` metres at the shaped height, a little under it so
## the voxel ground covers it where both are drawn, coloured as the ground's tops are.

const SHADER := """
shader_type spatial;
render_mode cull_back;
// Metres from the camera, across the ground, inside which the voxel ground is drawn instead.
uniform float near_cut = 250.0;
varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (length(world.xz - CAMERA_POSITION_WORLD.xz) < near_cut) {
		discard;
	}
	ALBEDO = pow(COLOR.rgb, vec3(2.2));
	ROUGHNESS = 0.95;
	SPECULAR = 0.15;
}
"""

## Metres the mesh sits under the ground, so the voxel ground hides it where both are drawn.
const SINK := 1.0


## Builds the mesh over `map`'s extent every `step` metres, coloured by `colour_at(x, z)`
## (a Color), drawn past `near_cut` metres from the camera.
func build(map: GroundShape, step: float, near_cut: float, colour_at: Callable) -> void:
	var area := map.extent()
	var n := int(ceil(area.size.x / step)) + 1
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	var colours := PackedColorArray()
	colours.resize(n * n)
	for j in n:
		for i in n:
			var x := area.position.x + i * step
			var z := area.position.y + j * step
			heights[j * n + i] = map.height_at(x, z) - SINK
			colours[j * n + i] = colour_at.call(x, z)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in n - 1:
		for i in n - 1:
			var corners: Array[int] = [j * n + i, j * n + i + 1, (j + 1) * n + i + 1, (j + 1) * n + i]
			# Wound to face up (Godot's front faces are clockwise seen from the front).
			for k: int in [0, 1, 2, 0, 2, 3]:
				var c := corners[k]
				st.set_color(colours[c])
				st.add_vertex(Vector3(area.position.x + (c % n) * step, heights[c], area.position.y + (c / n) * step))
	st.generate_normals()
	mesh = st.commit()
	var shader := Shader.new()
	shader.code = SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter(&"near_cut", near_cut)
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
