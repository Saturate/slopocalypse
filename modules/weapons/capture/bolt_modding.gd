extends Node3D
## Capture setup: the modding screen open on the bolt-action rifle, its slots (barrel, stock,
## bolt, magazine, optic) and stats, with the 4x scope picked on the draft in place of the
## 8x so the magnification shows worse.

const PLAYER := "res://modules/player/scenes/player.tscn"
const MODULE := "res://modules/weapons/weapons_module.gd"


func _ready() -> void:
	GunAssembly.override_build = "bolt_standard"
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
