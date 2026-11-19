extends Node3D
## Capture setup: first person with the bolt-action rifle. A shot from the hip, so the bolt
## being worked shows (the right hand goes to the bolt knob, the handle turns up, slides
## back and forward, turns down), then aiming through the 8x scope at a dummy 40 m off and
## a second shot.

const WORLD := "res://modules/world/scenes/world.tscn"
const PLAYER := "res://modules/player/scenes/player.tscn"
const DUMMY := "res://modules/training/scenes/dummy.tscn"
const MODULE := "res://modules/weapons/weapons_module.gd"

var _player: PlayerController
var _ticks := 0


func _ready() -> void:
	GunAssembly.override_build = "bolt_standard"
	await VoxelWorld.add_and_wait(self, WORLD)
	add_child((load(MODULE) as GDScript).new())
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
	var dummy: Node3D = (load(DUMMY) as PackedScene).instantiate()
	add_child(dummy)
	dummy.global_position = Vector3(0.0, 0.0, -40.0)


func _physics_process(_delta: float) -> void:
	if _player == null:
		return
	_ticks += 1
	var intent := _player.intent()
	intent.aim = _ticks > 150
	intent.fire = (_ticks > 40 and _ticks < 44) or (_ticks > 200 and _ticks < 204)
