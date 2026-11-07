extends Node3D
## Capture setup: every gun build from parts.json laid side by side on a plain, seen from
## the right, so a reviewer can check parts sit on their mounts and builds read differently.

const SPACING := 0.36


func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.6, 0.66)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.62, 0.66)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 60, 0)
	add_child(sun)
	var names := GunAssembly.build_names()
	for i in names.size():
		var gun := GunAssembly.build_model(GunAssembly.build(names[i]))
		add_child(gun)
		gun.position = Vector3(0, -i * SPACING, 0)
		var label := Label3D.new()
		label.text = names[i]
		label.font_size = 28
		label.position = Vector3(0.05, -i * SPACING + 0.15, 0.45)
		label.rotation_degrees = Vector3(0, 90, 0)
		add_child(label)
	var camera := Camera3D.new()
	camera.fov = 45.0
	add_child(camera)
	var middle := -SPACING * (names.size() - 1) / 2.0
	camera.position = Vector3(2.1, middle, -0.1)
	camera.look_at(Vector3(0, middle, -0.1))
	camera.current = true
