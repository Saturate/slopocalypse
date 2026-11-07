extends Node3D
## Capture setup: the modding screen open over the game, with a scope and a long magazine
## picked on the draft so the stats show better and worse values.

const PLAYER := "res://modules/player/scenes/player.tscn"
const MODULE := "res://modules/weapons/weapons_module.gd"


func _ready() -> void:
	var module: Node = (load(MODULE) as GDScript).new()
	add_child(module)
	var player: PlayerController = (load(PLAYER) as PackedScene).instantiate()
	player.set_meta(&"peer_id", 1)
	player.add_to_group(&"players")
	add_child(player)
	EventBus.publish(&"player.spawned", {"player": player, "local": false})
	var screen := ModdingScreen.new()
	screen.weapons = module
	screen.player = player
	add_child(screen)
	screen.open()
	screen.select("optic", "opt_scope_4x")
	screen.select("magazine", "mag_ar_45")
