extends SceneTree
## Builds the flat test world (`--world=flat`, used by the test range): a plain level plane
## with collision, the same sun and sky as the main world, a spawn point and a car spot. No
## terrain, scenery, road or tunnel.

const OUT := "res://modules/world/scenes/flat_world.tscn"
const SIZE := 1200.0
const GROUND := Color(0.42, 0.47, 0.32)


func _initialize() -> void:
	var root := Node3D.new()
	root.name = "World"
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.set_script(load("res://modules/world/scripts/flat_ground.gd"))
	ground.set("size", SIZE)
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box := BoxShape3D.new()
	box.size = Vector3(SIZE, 1.0, SIZE)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	ground.add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var plane := PlaneMesh.new()
	plane.size = Vector2(SIZE, SIZE)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = GROUND
	mat.roughness = 0.95
	plane.material = mat
	mesh.mesh = plane
	ground.add_child(mesh)
	root.add_child(ground)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.light_color = Color(1.0, 0.92, 0.8)
	sun.light_energy = 1.3
	sun.directional_shadow_max_distance = 120.0
	sun.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-40.0), deg_to_rad(40.0), 0.0)), Vector3.ZERO)
	root.add_child(sun)

	var env := WorldEnvironment.new()
	env.name = "Environment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.4, 0.54, 0.72)
	sky_mat.sky_horizon_color = Color(0.76, 0.76, 0.72)
	sky_mat.ground_horizon_color = Color(0.76, 0.76, 0.72)
	sky_mat.ground_bottom_color = Color(0.22, 0.22, 0.2)
	sky.sky_material = sky_mat
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.8
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.ssao_enabled = true
	env.environment = environment
	root.add_child(env)

	var spawn := Marker3D.new()
	spawn.name = "SpawnPoint"
	spawn.position = Vector3(0.0, 1.0, 0.0)
	spawn.add_to_group(&"spawn_point", true)
	root.add_child(spawn)
	var car := Marker3D.new()
	car.name = "CarSpawn"
	car.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(6.0, 1.0, -6.0))
	root.add_child(car)

	var result := SceneBuilder.pack_and_save(root, OUT)
	root.free()
	if result.error != OK:
		push_error(result.message)
		quit(1)
		return
	quit(0)
