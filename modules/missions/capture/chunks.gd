extends Node3D
## Capture setup: a blast on a wooden house's front and one on a brick house's: wall pieces
## come loose as tumbling chunks of themselves; the brick wall loses its bricks one by one
## and the pieces that lost most give way.

var _wood: MissionBuilding
var _brick: MissionBuilding
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
	env.environment.ambient_light_energy = 0.7
	add_child(env)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	floor_mesh.mesh = plane
	ground.add_child(floor_mesh)
	add_child(ground)
	_wood = _house("wood", Vector3(-6.0, 0.0, -10.0))
	_brick = _house("brick", Vector3(6.0, 0.0, -10.0))
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0.0, 4.0, 6.0)
	cam.look_at(Vector3(0.0, 1.2, -9.0), Vector3.UP)
	cam.current = true


func _house(material: String, at: Vector3) -> MissionBuilding:
	var b := MissionBuilding.new()
	b.spec = {"width": 8.0, "depth": 6.0, "wall_height": 3.0, "seed": 5, "paint": 0, "windows": 2.0, "material": material, "glass": "window_glass", "yaw": PI}
	add_child(b)
	b.position = at
	b.rotation.y = PI
	return b


func _physics_process(_delta: float) -> void:
	_ticks += 1
	if _ticks == 40:
		# The front faces the camera (turned round): local -Z is towards +Z here.
		var at := _wood.global_transform * Vector3(1.5, 1.0, -3.3)
		_wood.break_segments(_wood.server_blast(at, 2.5, 160.0, 1.6), [])
	if _ticks == 70:
		var at := _brick.global_transform * Vector3(-1.5, 1.0, -3.3)
		var bricks := _brick.server_blast_bricks(at, 1.8)
		_brick.knock_out(bricks, true)
		var weak := _brick.server_weakened()
		var fell := _brick.server_unsupported(weak)
		_brick.break_segments(weak, fell)
