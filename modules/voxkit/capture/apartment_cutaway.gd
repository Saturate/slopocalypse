extends Node3D
## Capture setup: a furnished apartment block cut open to see inside: with its street wall
## cut away (lit from the street), or with everything above head height on one floor sliced
## off and seen from above, like a doll's house.

## Slice the block at this height above the chosen floor and look down; 0 cuts the street wall.
var slice := 0.0
var floor_index := 1
var values := {"floors": 3.0, "stairwells": 1.0, "seed": 4.0}
var camera_from := Vector3(-9.0, 7.0, -22.0)
var camera_to := Vector3(0.0, 4.5, 0.0)


func _ready() -> void:
	var gen := VoxApartment.new()
	var plan := gen.layout(values)
	var model := gen.build(values)
	var d: float = plan["depth"]
	var wall: float = plan["wall"]
	var v: float = plan["voxel"]
	if slice > 0.0:
		var cut := float(plan["levels"][floor_index]) + slice
		model.carve_box(Vector3(-60.0, cut, -30.0), Vector3(60.0, 60.0, 30.0))
	else:
		model.carve_box(Vector3(-60.0, 0.0, -d / 2.0 - 3.0), Vector3(60.0, 40.0, -d / 2.0 + wall + v * 0.5))
	var mesh := MeshInstance3D.new()
	mesh.mesh = VoxGenerator.to_mesh(model)
	add_child(mesh)
	_people(plan)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.42, 0.25)
	ground.material_override = mat
	ground.position.y = -0.01
	add_child(ground)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.transform = Transform3D(Basis.from_euler(Vector3(-0.9, PI + 0.5, 0.0)), Vector3.ZERO)
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.8, 0.84, 0.88)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.8)
	env.environment.ambient_light_energy = 0.7
	env.environment.ssao_enabled = true
	add_child(env)
	var camera := Camera3D.new()
	camera.fov = 50.0
	add_child(camera)
	camera.current = true
	camera.transform = Transform3D(Basis.IDENTITY, camera_from).looking_at(camera_to)


## Player-sized figures (from the player module's data when it is there) standing in the
## kitchens and living rooms, to judge the scale by.
func _people(plan: Dictionary) -> void:
	var tall := 1.8
	var radius := 0.35
	var path := "res://modules/player/data/player.json"
	if FileAccess.file_exists(path):
		var body: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		tall = float(body["stand_height"])
		radius = float(body["radius"])
	var capsule := CapsuleMesh.new()
	capsule.height = tall
	capsule.radius = radius
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(1.0, 0.45, 0.1)
	var levels: Array = plan["levels"]
	var floors := [floor_index] if slice > 0.0 else range(levels.size())
	for i: int in floors:
		for fp: Dictionary in plan["flat_plans"]:
			for room: Dictionary in fp["rooms"]:
				if room["kind"] != "kitchen" and room["kind"] != "living":
					continue
				# Stand on the way in, which furniture keeps clear.
				var r: Rect2 = fp["entry"] if room["kind"] == "kitchen" else room["rect"]
				var at := r.get_center()
				if room["kind"] == "living":
					at.y = r.position.y + 0.6
				var person := MeshInstance3D.new()
				person.mesh = capsule
				person.material_override = paint
				person.position = Vector3(at.x, float(levels[i]) + tall / 2.0, at.y)
				add_child(person)
