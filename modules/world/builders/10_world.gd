extends SceneTree
## Builds modules/world/scenes/world.tscn: terrain node, light, sky, cover boxes, spawn point.

const OUT := "res://modules/world/scenes/world.tscn"
const CONFIG := "res://modules/world/data/world.json"


func _initialize() -> void:
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	if not config is Dictionary:
		push_error("%s: could not parse" % CONFIG)
		quit(1)
		return
	var heights := TerrainHeights.new(config)

	var root := Node3D.new()
	root.name = "World"

	var terrain := Node3D.new()
	terrain.name = "Terrain"
	terrain.set_script(load("res://modules/world/scripts/terrain_chunk.gd"))
	var ground := StandardMaterial3D.new()
	ground.albedo_color = Color(0.36, 0.45, 0.28)
	ground.roughness = 0.95
	terrain.set("config_path", CONFIG)
	terrain.set("material", ground)
	root.add_child(terrain)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-50.0), deg_to_rad(35.0), 0.0)), Vector3.ZERO)
	root.add_child(sun)

	var env := WorldEnvironment.new()
	env.name = "Environment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# Without GI, faces turned away from the sun read as black; lift the fill light.
	environment.ambient_light_energy = 1.6
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# Hides the hard edge where the 256 m test chunk ends.
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.62, 0.68, 0.75)
	environment.fog_density = 0.008
	environment.fog_sky_affect = 0.3
	env.environment = environment
	root.add_child(env)

	var cover_root := Node3D.new()
	cover_root.name = "Cover"
	root.add_child(cover_root)
	var crate := StandardMaterial3D.new()
	crate.albedo_color = Color(0.55, 0.5, 0.42)
	var index := 0
	for item: Dictionary in config["cover"]:
		cover_root.add_child(_cover_box(index, item, heights, crate))
		index += 1

	var spawn := Marker3D.new()
	spawn.name = "SpawnPoint"
	spawn.position = Vector3(0.0, heights.height_at(0.0, 0.0) + 1.0, 0.0)
	root.add_child(spawn)

	var result := SceneBuilder.pack_and_save(root, OUT)
	root.free()
	if result.error != OK:
		push_error(result.message)
		quit(1)
		return
	quit(0)


func _cover_box(index: int, item: Dictionary, heights: TerrainHeights, mat: Material) -> StaticBody3D:
	var size := Vector3(item["w"], item["h"], item["d"])
	var x: float = item["x"]
	var z: float = item["z"]
	var body := StaticBody3D.new()
	body.name = "Cover%d" % index
	# Sink the box a little so it never floats on a slope.
	body.position = Vector3(x, heights.height_at(x, z) + size.y / 2.0 - 0.3, z)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	mesh.mesh = box
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	return body
