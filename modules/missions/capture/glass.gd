extends Node3D
## Capture setup: a wooden mission building's side window from close outside, glass drawn
## see-through: the room and the far window show through it.

const BUILDING_AT := Vector3(0.0, 0.0, -8.0)


func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, 60.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.72, 0.82)
	env.environment.ambient_light_color = Color(0.7, 0.72, 0.75)
	env.environment.ambient_light_energy = 0.8
	add_child(env)
	var b := MissionBuilding.new()
	b.spec = {"width": 8.0, "depth": 6.0, "wall_height": 3.0, "seed": 5, "paint": 0, "windows": 2.0, "material": "wood", "glass": "window_glass", "yaw": 0.0}
	add_child(b)
	b.position = BUILDING_AT
	var cam := Camera3D.new()
	add_child(cam)
	# Outside the right-hand wall, level with its window, looking in across the room.
	cam.position = BUILDING_AT + Vector3(6.0, 1.6, 0.6)
	cam.look_at(BUILDING_AT + Vector3(-4.0, 1.4, 0.0), Vector3.UP)
	cam.current = true
