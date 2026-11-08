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

	# The tunnel the road (and the players) come out of; built at runtime from world.json.
	var tunnel := Node3D.new()
	tunnel.name = "StartTunnel"
	tunnel.set_script(load("res://modules/world/scripts/start_tunnel.gd"))
	tunnel.set("config_path", CONFIG)
	root.add_child(tunnel)

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
	root.add_child(env)

	var cover_root := Node3D.new()
	cover_root.name = "Cover"
	root.add_child(cover_root)
	# Weathered concrete and timber (CC0 ambientCG) instead of flat colours.
	var palette: Array[StandardMaterial3D] = [
		WorldMaterials.triplanar("Concrete034", Color(0.6, 0.59, 0.56), 2.0),
		WorldMaterials.triplanar("Planks037A", Color(0.7, 0.64, 0.56), 1.5),
		WorldMaterials.triplanar("Concrete034", Color(0.48, 0.47, 0.45), 2.0),
	]
	var index := 0
	for item: Dictionary in config["cover"]:
		cover_root.add_child(_cover_box(index, item, heights, palette[index % palette.size()]))
		index += 1

	root.add_child(_boundary(heights.extent()))

	var spawn := Marker3D.new()
	spawn.name = "SpawnPoint"
	spawn.position = Vector3(0.0, heights.height_at(0.0, 0.0) + 1.0, 0.0)
	root.add_child(spawn)

	# The car waits on the road just outside the tunnel, nose down the road (cars drive along
	# their +Z, the road runs along -Z).
	var car := Marker3D.new()
	car.name = "CarSpawn"
	var car_z := 0.0
	var car_side := 0.0
	if heights.has_tunnel():
		car_z = float(heights.start["portal_z"]) - float(heights.start["car_distance"])
		car_side = float(heights.start["car_side"])
	var car_x := (heights.road.x_at(car_z) if heights.road != null else 0.0) + car_side
	car.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(car_x, heights.height_at(car_x, car_z) + 1.0, car_z))
	root.add_child(car)

	var result := SceneBuilder.pack_and_save(root, OUT)
	root.free()
	if result.error != OK:
		push_error(result.message)
		quit(1)
		return
	quit(0)


## Invisible walls just inside the world's edge so nobody walks or drives off it.
func _boundary(area: Rect2) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Boundary"
	var inset := 1.0
	var left := area.position.x + inset
	var right := area.end.x - inset
	var far := area.position.y + inset
	var near := area.end.y - inset
	var mid := area.get_center()
	# Tall enough to reach well below the voxel depth, so nothing slips under the wall.
	var height := 400.0
	var thickness := 2.0
	var walls := [
		["North", Vector3(mid.x, 0.0, far), Vector3(area.size.x, height, thickness)],
		["South", Vector3(mid.x, 0.0, near), Vector3(area.size.x, height, thickness)],
		["West", Vector3(left, 0.0, mid.y), Vector3(thickness, height, area.size.y)],
		["East", Vector3(right, 0.0, mid.y), Vector3(thickness, height, area.size.y)],
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
