extends SceneTree
## Builds modules/world/scenes/world.tscn: terrain node, scenery, light, sky, boundary, spawn
## point. The map is built at runtime, so the root (WorldRoot) puts the spawn, the car and the
## boundary walls on it then.

const OUT := "res://modules/world/scenes/world.tscn"
const CONFIG := "res://modules/world/data/world.json"


func _initialize() -> void:
	var root := Node3D.new()
	root.name = "World"
	root.set_script(load("res://modules/world/scripts/world_root.gd"))
	root.set("config_path", CONFIG)

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

	# Late-afternoon sun: low and warm, long shadows, light shafts through the haze.
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.light_color = Color(1.0, 0.88, 0.72)
	sun.light_energy = 1.4
	sun.light_volumetric_fog_energy = 1.6
	sun.shadow_blur = 1.2
	sun.directional_shadow_max_distance = 160.0
	sun.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-24.0), deg_to_rad(40.0), 0.0)), Vector3.ZERO)
	# Found by the day and night cycle, which moves it and recolours the sky through the day.
	sun.add_to_group(&"sun", true)
	root.add_child(sun)

	var env := WorldEnvironment.new()
	env.name = "Environment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	# A hazy, slightly washed sky rather than a clean postcard blue.
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.4, 0.54, 0.72)
	sky_mat.sky_horizon_color = Color(0.76, 0.76, 0.72)
	sky_mat.ground_horizon_color = Color(0.76, 0.76, 0.72)
	sky_mat.ground_bottom_color = Color(0.22, 0.22, 0.2)
	sky_mat.sun_angle_max = 20.0
	sky.sky_material = sky_mat
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.7
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 1.0
	# Indirect bounce light and contact occlusion do most of the "grounded" work.
	environment.ssil_enabled = true
	environment.ssil_intensity = 1.2
	environment.ssao_enabled = true
	environment.ssao_radius = 1.0
	environment.ssao_intensity = 2.0
	environment.glow_enabled = true
	environment.glow_intensity = 0.3
	environment.glow_bloom = 0.03
	# Grounded grade: less saturation, a bit more contrast, warm highlights.
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 0.9
	environment.adjustment_contrast = 1.12
	environment.adjustment_brightness = 1.0
	# Volumetric fog gives depth and sun shafts; it is cheap at these settings on Forward+.
	environment.volumetric_fog_enabled = true
	environment.volumetric_fog_density = 0.006
	environment.volumetric_fog_albedo = Color(0.82, 0.8, 0.76)
	environment.volumetric_fog_anisotropy = 0.6
	environment.volumetric_fog_length = 120.0
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.7, 0.68, 0.64)
	environment.fog_density = 0.002
	environment.fog_aerial_perspective = 0.4
	environment.fog_sky_affect = 0.3
	env.environment = environment
	env.add_to_group(&"world_environment", true)
	root.add_child(env)

	root.add_child(_boundary())

	var spawn := Marker3D.new()
	spawn.name = "SpawnPoint"
	spawn.add_to_group(&"spawn_point", true)
	root.add_child(spawn)

	var car := Marker3D.new()
	car.name = "CarSpawn"
	root.add_child(car)

	var result := SceneBuilder.pack_and_save(root, OUT)
	root.free()
	if result.error != OK:
		push_error(result.message)
		quit(1)
		return
	quit(0)


## Invisible walls just inside the world's edge so nobody walks or drives off it; WorldRoot
## sizes and places them on the map.
func _boundary() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Boundary"
	for side: String in ["North", "South", "West", "East"]:
		var shape := CollisionShape3D.new()
		shape.name = side
		shape.shape = BoxShape3D.new()
		body.add_child(shape)
	return body
