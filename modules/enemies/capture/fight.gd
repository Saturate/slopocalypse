extends Node3D
## Capture setup: first person, a squad of three enemy soldiers 25 m ahead turning to
## face the player and opening fire (tracers), the HUD showing the hits.

const WORLD := "res://modules/world/scenes/world.tscn"
const PLAYER := "res://modules/player/scenes/player.tscn"
const WEAPONS := "res://modules/weapons/weapons_module.gd"
const ENEMIES := "res://modules/enemies/enemies_module.gd"

var _player: PlayerController


func _ready() -> void:
	await VoxelWorld.add_and_wait(self, WORLD)
	var scenery := find_child("Scenery", true, false) as Node3D
	if scenery != null:
		scenery.visible = false
	add_child((load(WEAPONS) as GDScript).new())
	var enemies: Node = (load(ENEMIES) as GDScript).new()
	add_child(enemies)
	_player = (load(PLAYER) as PackedScene).instantiate()
	_player.set_meta(&"peer_id", 1)
	_player.add_to_group(&"players")
	add_child(_player)
	_player.global_position = Vector3(0.0, 0.5, 0.0)
	EventBus.publish(&"player.spawned", {"player": _player, "local": true})
	var animator := PlayerBodyAnimator.new()
	animator.name = "BodyAnimator"
	animator.player = _player
	_player.add_child(animator)
	PlayerBody.first_person(_player.get_node("Body"))
	(_player.get_node("Head/Camera") as Camera3D).current = true
	var hud := PlayerHud.new()
	hud.player = _player
	_player.add_child(hud)
	enemies.call(&"server_spawn_squad", 3, Vector3(2.0, 0.0, -25.0))
