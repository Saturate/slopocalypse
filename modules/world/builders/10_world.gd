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

	# Smooth voxel terrain, built at runtime by VoxelWorld (Voxel Tools) from world.json.
	var terrain := Node3D.new()
	terrain.name = "Terrain"
	terrain.set_script(load("res://modules/world/scripts/voxel_world.gd"))
	terrain.set("config_path", CONFIG)
	root.add_child(terrain)

	var scenery := Node3D.new()
	scenery.name = "Scenery"
	scenery.set_script(load("res://modules/world/scripts/scenery_scatter.gd"))
	scenery.set("config_path", CONFIG)
	root.add_child(scenery)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.25
	sun.shadow_blur = 2.0
	# Fully black shadows read as holes in a bright low-poly scene.
	sun.shadow_opacity = 0.8
	sun.directional_shadow_max_distance = 140.0
	sun.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-42.0), deg_to_rad(35.0), 0.0)), Vector3.ZERO)
	root.add_child(sun)

	var env := WorldEnvironment.new()
	env.name = "Environment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.5, 0.78)
	sky_mat.sky_horizon_color = Color(0.72, 0.78, 0.84)
	sky_mat.ground_horizon_color = Color(0.72, 0.78, 0.84)
	sky_mat.ground_bottom_color = Color(0.3, 0.34, 0.3)
	sky.sky_material = sky_mat
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# Without GI, faces turned away from the sun read as black; lift the fill light.
	environment.ambient_light_energy = 1.5
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 1.0
	# Ambient occlusion grounds props and trees; cheap at this scene size.
	environment.ssao_enabled = true
	environment.ssao_radius = 1.2
	environment.ssao_intensity = 1.6
	environment.glow_enabled = true
	environment.glow_intensity = 0.4
	environment.glow_bloom = 0.05
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.12
	environment.adjustment_contrast = 1.05
	# Aerial haze hides the hard edge where the 256 m test chunk ends.
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.68, 0.74, 0.8)
	environment.fog_density = 0.0035
	environment.fog_aerial_perspective = 0.3
	environment.fog_sky_affect = 0.25
	env.environment = environment
	root.add_child(env)

	var cover_root := Node3D.new()
	cover_root.name = "Cover"
	root.add_child(cover_root)
	# A small palette of concrete and timber so cover doesn't read as one flat colour.
	var palette: Array[StandardMaterial3D] = []
	for c: Color in [Color(0.58, 0.56, 0.52), Color(0.5, 0.48, 0.45), Color(0.52, 0.4, 0.28), Color(0.44, 0.34, 0.24)]:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.85
		palette.append(m)
	var index := 0
	for item: Dictionary in config["cover"]:
		cover_root.add_child(_cover_box(index, item, heights, palette[index % palette.size()]))
		index += 1

	root.add_child(_boundary(heights.size))

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


## Invisible walls just inside the chunk edge so nobody walks or drives off the world.
func _boundary(size: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Boundary"
	var half := size / 2.0 - 1.0
	# Tall enough to reach well below the voxel depth, so nothing slips under the wall.
	var height := 400.0
	var thickness := 2.0
	var walls := [
		["North", Vector3(0.0, 0.0, -half), Vector3(size, height, thickness)],
		["South", Vector3(0.0, 0.0, half), Vector3(size, height, thickness)],
		["West", Vector3(-half, 0.0, 0.0), Vector3(thickness, height, size)],
		["East", Vector3(half, 0.0, 0.0), Vector3(thickness, height, size)],
	]
	for w: Array in walls:
		var shape := CollisionShape3D.new()
		shape.name = w[0]
		var box := BoxShape3D.new()
		box.size = w[2]
		shape.shape = box
		shape.position = w[1]
		body.add_child(shape)
	return body


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
