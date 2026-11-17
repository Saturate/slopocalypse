extends Node3D
## Capture setup: first person with the thermal scope build. Three soldier stand-ins 20 to
## 25 m out: one in the open, one inside a smoke plume, one behind a wall. At the hip the
## plume hides its soldier; through the thermal scope the open one and the one in the smoke
## show white and the one behind the wall stays hidden.

const WORLD := "res://modules/world/scenes/world.tscn"
const PLAYER := "res://modules/player/scenes/player.tscn"
const MODULE := "res://modules/weapons/weapons_module.gd"
const SMOKE := "res://modules/smoke/smoke_module.gd"

var _player: PlayerController
var _smoke: Node
var _ticks := 0


func _ready() -> void:
	GunAssembly.override_build = "ar_thermal"
	await VoxelWorld.add_and_wait(self, WORLD)
	add_child((load(MODULE) as GDScript).new())
	_smoke = (load(SMOKE) as GDScript).new()
	add_child(_smoke)
	_player = (load(PLAYER) as PackedScene).instantiate()
	add_child(_player)
	_player.global_position = Vector3(0.0, 0.1, 0.0)
	EventBus.publish(&"player.spawned", {"player": _player, "local": true})
	var animator := PlayerBodyAnimator.new()
	animator.name = "BodyAnimator"
	animator.player = _player
	_player.add_child(animator)
	var feel := PlayerCameraFeel.new()
	feel.player = _player
	feel.camera = _player.get_node("Head/Camera")
	_player.add_child(feel)
	PlayerBody.first_person(_player.get_node("Body"))
	(_player.get_node("Head/Camera") as Camera3D).current = true
	for at: Vector3 in [Vector3(-3.0, 0.0, -20.0), Vector3(0.5, 0.0, -24.0), Vector3(4.0, 0.0, -22.0)]:
		var soldier: Node3D = (load(PLAYER) as PackedScene).instantiate()
		soldier.add_to_group(&"enemies")
		add_child(soldier)
		soldier.global_position = at
		soldier.set_physics_process(false)
	var wall := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.5, 3.0, 0.4)
	wall.mesh = box
	add_child(wall)
	wall.global_position = Vector3(4.0, 1.5, -19.5)


func _physics_process(_delta: float) -> void:
	if _player == null:
		return
	_ticks += 1
	if _ticks == 5:
		var field := _smoke.get_node("Field")
		field.call(&"server_spawn", "blast", Vector3(0.5, 1.0, -24.0))
	var intent := _player.intent()
	intent.aim = _ticks > 200
