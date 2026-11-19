extends Node3D
## Capture setup: three soldiers stand in a row in front of a wall and are shot from the camera's
## side again and again (the middle one through the head); blood sprays out behind each of them
## and marks build up on the wall and the ground behind (#385).

const WORLD := "res://modules/world/scenes/world.tscn"
const PLAYER := "res://modules/player/scenes/player.tscn"
const XS: Array[float] = [-2.0, 0.0, 2.0]
const WALL_Z := -2.2
## Physics ticks between shots, taking the soldiers in turn.
const EVERY := 8
## Ticks for the soldiers to land on their feet; then they hold still (the road slopes).
const LANDED := 45

var _soldiers: Array[PlayerController] = []
var _camera := Camera3D.new()
var _ticks := 0
var _shot := 0


func _ready() -> void:
	await VoxelWorld.add_and_wait(self, WORLD)
	for x in XS:
		var soldier: PlayerController = (load(PLAYER) as PackedScene).instantiate()
		soldier.add_to_group(&"enemies")
		add_child(soldier)
		soldier.global_position = Vector3(x, 0.5, 0.0)
		var animator := PlayerBodyAnimator.new()
		animator.name = "BodyAnimator"
		animator.player = soldier
		soldier.add_child(animator)
		_soldiers.append(soldier)
	# The road at the world's origin is level with y = 0 (the ragdoll capture stands there too).
	var ground_y := 0.0
	_wall(Vector3(0.0, ground_y + 1.5, WALL_Z - 0.2), Vector3(8.0, 3.0, 0.4))
	var effects := BloodEffects.new()
	add_child(effects)
	add_child(_camera)
	_camera.current = true
	# From the side, so drops flying from the bodies to the wall are seen crossing the gap.
	_camera.global_position = Vector3(5.5, ground_y + 1.8, 1.2)
	_camera.look_at(Vector3(-0.3, ground_y + 1.0, -1.1))


func _wall(at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.6, 0.55)
	bm.material = mat
	mesh.mesh = bm
	body.add_child(mesh)
	add_child(body)
	body.global_position = at


func _physics_process(_delta: float) -> void:
	if _soldiers.is_empty():
		return
	_ticks += 1
	if _ticks == LANDED:
		for soldier in _soldiers:
			soldier.set_physics_process(false)
	if _ticks <= LANDED or _ticks % EVERY != 0:
		return
	var i := _shot % _soldiers.size()
	_shot += 1
	var soldier := _soldiers[i]
	var to := soldier.global_position + Vector3(0.0, 0.9 + 0.15 * float(_shot % 3), 0.3)
	if i == 1:
		to = (soldier.get_node("Head") as Node3D).global_position + Vector3(0.0, 0.05, 0.3)
	var from := to + Vector3(0.6, 0.1, 6.0)
	EventBus.publish(&"weapon.fired", {"from": from, "to": to, "target": soldier, "collider": soldier, "damage": 10.0})
