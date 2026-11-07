extends Node3D
## Capture setup: first person by a loot pile near the spawn, looking down at it with the
## pickup prompt showing. Parts lie on the ground as their own models.

const WORLD := "res://modules/world/scenes/world.tscn"
const PLAYER := "res://modules/player/scenes/player.tscn"
const INVENTORY := "res://modules/inventory/inventory_module.gd"
const WEAPONS := "res://modules/weapons/weapons_module.gd"

var _player: PlayerController
var _ticks := 0


func _ready() -> void:
	await VoxelWorld.add_and_wait(self, WORLD)
	add_child((load(WEAPONS) as GDScript).new())
	add_child((load(INVENTORY) as GDScript).new())
	_player = (load(PLAYER) as PackedScene).instantiate()
	_player.set_meta(&"peer_id", 1)
	_player.add_to_group(&"players")
	add_child(_player)
	_player.global_position = Vector3(3.0, 0.1, -2.6)
	EventBus.publish(&"player.spawned", {"player": _player, "local": true})
	var animator := PlayerBodyAnimator.new()
	animator.name = "BodyAnimator"
	animator.player = _player
	_player.add_child(animator)
	PlayerBody.first_person(_player.get_node("Body"))
	(_player.get_node("Head/Camera") as Camera3D).current = true
	EventBus.publish(&"world.ready", {"spawn": Vector3(0.0, _player.global_position.y, 0.0)})


func _physics_process(_delta: float) -> void:
	if _player == null:
		return
	_ticks += 1
	if _ticks < 30:
		_player.intent().look_delta.y += 0.022
