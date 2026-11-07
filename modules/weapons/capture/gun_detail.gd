extends Node3D
## Capture setup: the standard build up close, the camera circling it, so a reviewer can
## judge detail (rail teeth, slots, optic glass, magazine curve) from every side.

const ORBIT_SECONDS := 4.0
const RADIUS := 1.05

var _camera: Camera3D
var _t := 0.0


func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.6, 0.66)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.62, 0.66)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 40, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var build := "ar_standard"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--build="):
			build = arg.trim_prefix("--build=")
	add_child(GunAssembly.build_model(GunAssembly.build(build)))
	_camera = Camera3D.new()
	_camera.fov = 40.0
	add_child(_camera)
	_camera.current = true
	_place()


func _process(delta: float) -> void:
	_t += delta
	_place()


func _place() -> void:
	var a := TAU * _t / ORBIT_SECONDS + 0.6
	var focus := Vector3(0, 0.0, -0.12)
	_camera.position = focus + Vector3(cos(a) * RADIUS, 0.22, sin(a) * RADIUS)
	_camera.look_at(focus)
