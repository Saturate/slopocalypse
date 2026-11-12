extends Node3D
## Capture setup: a brick mission building up close, then a few rifle rounds into its front:
## bricks in mortar joints, a running bond, chips off brick and mortar.

const BUILDING_AT := Vector3(0.0, 0.0, -8.0)

var _building: MissionBuilding
var _ticks := 0


func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.72, 0.82)
	env.environment.ambient_light_color = Color(0.7, 0.72, 0.75)
	env.environment.ambient_light_energy = 0.6
	add_child(env)
	_building = MissionBuilding.new()
	_building.spec = {"width": 8.0, "depth": 6.0, "wall_height": 3.0, "seed": 5, "paint": 1, "windows": 2.0, "material": "brick", "glass": "window_glass", "yaw": 0.0}
	add_child(_building)
	_building.position = BUILDING_AT
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(2.5, 1.8, -8.0 + 3.0 + 4.5)
	cam.look_at(BUILDING_AT + Vector3(0.0, 1.4, 3.0), Vector3.UP)
	cam.current = true


func _physics_process(_delta: float) -> void:
	_ticks += 1
	if _ticks >= 60 and _ticks < 90:
		var k := _ticks - 60
		var to := _building.global_transform * Vector3(-2.5 + k * 0.17, 0.5 + fmod(k * 0.37, 1.0) * 1.8, -3.0)
		var from := to + Vector3(0.0, 0.2, 10.0)
		_building.bullet_mark(to, to - from)
