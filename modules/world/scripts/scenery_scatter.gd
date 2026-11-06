class_name SceneryScatter
extends Node3D
## Scatters low-poly trees, rocks and grass over the terrain from a seed, so the server
## and every client place the same trees in the same spots. Trees and rocks get collision
## everywhere; the visuals (and grass, which has no collision) are client-only.

@export_file("*.json") var config_path: String = "res://modules/world/data/world.json"

const REQUIRED := {"trees": TYPE_FLOAT, "rocks": TYPE_FLOAT, "grass": TYPE_FLOAT, "clear_radius": TYPE_FLOAT, "max_steepness": TYPE_FLOAT, "seed": TYPE_FLOAT}

var _heights: TerrainHeights
var _rng := RandomNumberGenerator.new()
var _visual := DisplayServer.get_name() != "headless"


func _ready() -> void:
	var data: Variant = Data.load_json(config_path)
	if not data is Dictionary or not Data.require(config_path, data, TerrainHeights.REQUIRED):
		return
	var world: Dictionary = data
	if not world.has("scatter") or not Data.require(config_path + " scatter", world["scatter"], REQUIRED):
		return
	var cfg: Dictionary = world["scatter"]
	_heights = TerrainHeights.new(world)
	var collision := StaticBody3D.new()
	collision.name = "SceneryCollision"
	add_child(collision)
	_rng.seed = int(cfg["seed"])
	_place_trees(int(cfg["trees"]), cfg, collision)
	_place_rocks(int(cfg["rocks"]), cfg, collision)
	if _visual:
		_place_grass(int(cfg["grass"]), cfg)


## A spot on gentle ground, away from the spawn pad and the chunk edge.
func _random_spot(cfg: Dictionary) -> Variant:
	var half := _heights.size / 2.0 - 6.0
	for attempt in 12:
		var x := _rng.randf_range(-half, half)
		var z := _rng.randf_range(-half, half)
		if Vector2(x, z).length() < float(cfg["clear_radius"]):
			continue
		var s := 1.0
		var dx := _heights.height_at(x + s, z) - _heights.height_at(x - s, z)
		var dz := _heights.height_at(x, z + s) - _heights.height_at(x, z - s)
		if Vector2(dx, dz).length() / (2.0 * s) > float(cfg["max_steepness"]):
			continue
		return Vector3(x, _heights.height_at(x, z), z)
	return null


func _place_trees(count: int, cfg: Dictionary, collision: StaticBody3D) -> void:
	var trunks: Array[Transform3D] = []
	var canopies: Array[Transform3D] = []
	var colours: Array[Color] = []
	for i in count:
		var spot: Variant = _random_spot(cfg)
		if not spot is Vector3:
			continue
		var at: Vector3 = spot
		var scale := _rng.randf_range(0.8, 1.5)
		var yaw := _rng.randf() * TAU
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale)
		trunks.append(Transform3D(basis, at))
		canopies.append(Transform3D(basis, at + Vector3.UP * 1.6 * scale))
		colours.append(Color(0.2, 0.38, 0.18).lerp(Color(0.32, 0.45, 0.2), _rng.randf()))
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.25 * scale
		cyl.height = 3.0 * scale
		shape.shape = cyl
		shape.position = at + Vector3.UP * 1.5 * scale
		collision.add_child(shape)
	if _visual:
		_multimesh("Trunks", _trunk_mesh(), trunks, [])
		_multimesh("Canopies", _canopy_mesh(), canopies, colours)


func _place_rocks(count: int, cfg: Dictionary, collision: StaticBody3D) -> void:
	var transforms: Array[Transform3D] = []
	var colours: Array[Color] = []
	for i in count:
		var spot: Variant = _random_spot(cfg)
		if not spot is Vector3:
			continue
		var at: Vector3 = spot
		var size := _rng.randf_range(0.4, 1.6)
		var basis := Basis.from_euler(Vector3(_rng.randf() * 0.4, _rng.randf() * TAU, _rng.randf() * 0.4)).scaled(Vector3(size, size * _rng.randf_range(0.5, 0.9), size))
		transforms.append(Transform3D(basis, at + Vector3.DOWN * size * 0.15))
		var grey := _rng.randf_range(0.38, 0.52)
		colours.append(Color(grey, grey * 0.98, grey * 0.95))
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = size * 0.45
		shape.shape = sphere
		shape.position = at + Vector3.UP * size * 0.15
		collision.add_child(shape)
	if _visual:
		_multimesh("Rocks", _rock_mesh(), transforms, colours)


func _place_grass(count: int, cfg: Dictionary) -> void:
	var transforms: Array[Transform3D] = []
	var colours: Array[Color] = []
	var half := _heights.size / 2.0 - 2.0
	for i in count:
		var x := _rng.randf_range(-half, half)
		var z := _rng.randf_range(-half, half)
		var s := _rng.randf_range(0.6, 1.3)
		transforms.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.7, 1.4), s)), Vector3(x, _heights.height_at(x, z), z)))
		colours.append(Color(0.33, 0.5, 0.22).lerp(Color(0.5, 0.58, 0.28), _rng.randf()))
	var mm := _multimesh("Grass", _grass_mesh(), transforms, colours)
	mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Grass far away is noise; fade it out with distance to keep the horizon clean.
	mm.visibility_range_end = 70.0
	mm.visibility_range_end_margin = 10.0
	mm.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


func _multimesh(node_name: String, mesh: Mesh, transforms: Array[Transform3D], colours: Array[Color]) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colours.is_empty()
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colours[i])
	var inst := MultiMeshInstance3D.new()
	inst.name = node_name
	inst.multimesh = mm
	add_child(inst)
	return inst


func _material(colour: Color, use_instance_colour: bool, double_sided: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.9
	mat.vertex_color_use_as_albedo = use_instance_colour
	# Instance tints are picked in sRGB; read as linear they wash out to near white.
	mat.vertex_color_is_srgb = true
	if double_sided:
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _trunk_mesh() -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.12
	m.bottom_radius = 0.2
	m.height = 2.0
	m.radial_segments = 6
	m.rings = 1
	m.material = _material(Color(0.36, 0.26, 0.17), false)
	# CylinderMesh is centred; lift it so the base sits on the ground.
	var st := SurfaceTool.new()
	st.append_from(m, 0, Transform3D(Basis.IDENTITY, Vector3.UP * 1.0))
	var out := st.commit()
	out.surface_set_material(0, m.material)
	return out


func _canopy_mesh() -> Mesh:
	# Two stacked low-poly cones read as a stylised conifer.
	var st := SurfaceTool.new()
	var mat := _material(Color.WHITE, true)
	for tier in [[1.3, 2.0, 0.6], [0.95, 1.6, 1.7]]:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = tier[0]
		cone.height = tier[1]
		cone.radial_segments = 7
		cone.rings = 1
		st.append_from(cone, 0, Transform3D(Basis.IDENTITY, Vector3.UP * tier[2]))
	var out := st.commit()
	out.surface_set_material(0, mat)
	return out


func _rock_mesh() -> Mesh:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 6
	sphere.rings = 3
	var st := SurfaceTool.new()
	st.append_from(sphere, 0, Transform3D.IDENTITY)
	# Faceted rocks: de-indexing gives each face its own vertices, so generated normals are
	# flat. (generate_normals' argument flips normals inward; it is not "flat shading".)
	st.deindex()
	st.generate_normals()
	var out := st.commit()
	out.surface_set_material(0, _material(Color.WHITE, true))
	return out


func _grass_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	# A tuft of five thin blades fanned around the centre. Each blade is written with both
	# windings and an up normal, instead of disabling culling: Godot flips the normal on
	# back faces, which lights them from below and turns half the grass black.
	for i in 5:
		var angle := TAU * float(i) / 5.0
		var side := Vector3(cos(angle), 0.0, sin(angle)) * 0.06
		var lean := Vector3(cos(angle + 0.6), 0.0, sin(angle + 0.6)) * 0.12
		var tip := Vector3.UP * 0.35 + lean
		for tri in [[-side, side, tip], [side, -side, tip]]:
			for v: Vector3 in tri:
				st.add_vertex(v)
	var out := st.commit()
	out.surface_set_material(0, _material(Color.WHITE, true))
	return out
