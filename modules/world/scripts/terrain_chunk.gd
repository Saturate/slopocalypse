class_name TerrainChunk
extends Node3D
## Builds the terrain at runtime from data instead of storing a large mesh in the scene.
## The headless server only needs collision, so it skips the mesh.

@export_file("*.json") var config_path: String = "res://modules/world/data/world.json"
@export var material: Material

var heights: TerrainHeights


func _ready() -> void:
	var data: Variant = Data.load_json(config_path)
	if not data is Dictionary or not Data.require(config_path, data, TerrainHeights.REQUIRED):
		return
	heights = TerrainHeights.new(data)
	_build_collision()
	if DisplayServer.get_name() != "headless":
		_build_mesh()


func _build_collision() -> void:
	var n := heights.resolution
	var shape := HeightMapShape3D.new()
	shape.map_width = n
	shape.map_depth = n
	var samples := PackedFloat32Array()
	samples.resize(n * n)
	var half := heights.size / 2.0
	var step := heights.spacing()
	for iz in n:
		for ix in n:
			samples[iz * n + ix] = heights.height_at(ix * step - half, iz * step - half)
	shape.map_data = samples
	var body := StaticBody3D.new()
	body.name = "Collision"
	var col := CollisionShape3D.new()
	col.shape = shape
	# HeightMapShape3D samples are one unit apart; scale x/z to the grid spacing.
	col.scale = Vector3(step, 1.0, step)
	body.add_child(col)
	add_child(body)


func _build_mesh() -> void:
	var n := heights.resolution
	var half := heights.size / 2.0
	var step := heights.spacing()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in n:
		for ix in n:
			var x := ix * step - half
			var z := iz * step - half
			st.set_uv(Vector2(float(ix) / (n - 1), float(iz) / (n - 1)))
			st.add_vertex(Vector3(x, heights.height_at(x, z), z))
	for iz in n - 1:
		for ix in n - 1:
			var a := iz * n + ix
			var b := a + 1
			var c := a + n
			var d := c + 1
			# Godot treats clockwise triangles (seen from the front) as front faces.
			st.add_index(a)
			st.add_index(b)
			st.add_index(c)
			st.add_index(b)
			st.add_index(d)
			st.add_index(c)
	st.generate_normals()
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = st.commit()
	if material != null:
		mesh_instance.material_override = material
	add_child(mesh_instance)
