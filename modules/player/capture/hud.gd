extends Node3D
## Capture setup: the local HUD: health bar, then a hit (red flash, bar drops), then dying
## (death screen with the respawn countdown).

const WORLD := "res://modules/world/scenes/world.tscn"
const PLAYER := "res://modules/player/scenes/player.tscn"
const DUMMY := "res://modules/training/scenes/dummy.tscn"
const MODULE := "res://modules/weapons/weapons_module.gd"

var _player: PlayerController
var _ticks := 0


func _ready() -> void:
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
	var hud := PlayerHud.new()
	hud.player = _player
	_player.add_child(hud)
	var dummy: Node3D = (load(DUMMY) as PackedScene).instantiate()
	add_child(dummy)
	dummy.global_position = Vector3(0.0, 0.0, -12.0)


func _physics_process(_delta: float) -> void:
	if _player == null:
		return
	_ticks += 1
	var health := _player.get_node("Health") as HealthComponent
	if _ticks == 60:
		health.server_apply_damage(45.0)
	if _ticks == 140:
		health.server_apply_damage(100.0)
		EventBus.publish(&"player.died", {"player": _player})
