extends Node3D
## Capture setup: a rocket from a launcher's distance into a brick wall sample: the smoke
## trail, the blast, bricks knocked out, the pieces coming loose and settling as rubble.

const WEAPONS := "res://modules/weapons/weapons_module.gd"

var _weapons: Node
var _wall: MissionBuilding
var _ticks := 0


func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, -30.0, 0.0)
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
	box.size = Vector3(120, 1, 120)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	var plane := MeshInstance3D.new()
	plane.mesh = PlaneMesh.new()
	(plane.mesh as PlaneMesh).size = Vector2(120, 120)
	ground.add_child(plane)
	add_child(ground)
	_weapons = (load(WEAPONS) as GDScript).new()
	add_child(_weapons)
	_wall = MissionBuilding.new()
	_wall.spec = {"kind": "wall", "label": "Brick", "material": "brick", "width": 4.0, "depth": 0.225, "wall_height": 3.0, "seed": 3, "yaw": 0.0}
	add_child(_wall)
	_wall.position = Vector3(0, 0, -25)
	EventBus.subscribe(&"explosion", _on_blast)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(7.0, 2.5, -12.0)
	cam.look_at(Vector3(0, 1.5, -21.0), Vector3.UP)
	cam.current = true


func _physics_process(_delta: float) -> void:
	_ticks += 1
	if _ticks == 30:
		_weapons.call(&"spawn_rocket", Vector3(0.4, 1.4, 0.0), Vector3(0, 0, -55), null)


## What the missions module does on a blast, for this lone wall: bricks out, pieces broken.
func _on_blast(p: Dictionary) -> void:
	var at: Vector3 = p["position"]
	var radius := float(p.get("radius", 2.8))
	_wall.knock_out(_wall.server_blast_bricks(at, radius * 0.7), true)
	var broke := _wall.server_blast(at, radius, 140.0, 1.6)
	broke.append_array(_wall.server_weakened())
	_wall.break_segments(broke, _wall.server_unsupported(broke))
