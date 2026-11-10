extends Node3D
## Capture setup: the inventory screen open with the starting kit, one item mid-drag over
## a free spot.

const PLAYER := "res://modules/player/scenes/player.tscn"
const MODULE := "res://modules/inventory/inventory_module.gd"

var _screen: InventoryScreen


func _ready() -> void:
	var module: Node = (load(MODULE) as GDScript).new()
	add_child(module)
	var player: Node = (load(PLAYER) as PackedScene).instantiate()
	player.set_meta(&"peer_id", 1)
	add_child(player)
	EventBus.publish(&"player.spawned", {"player": player, "local": false})
	_screen = InventoryScreen.new()
	_screen.inventory = module
	_screen.peer = 1
	add_child(_screen)
	_screen.open()
	var gear: InventoryGear = module.call(&"grid_of", 1)
	var item: Dictionary = gear.items("backpack")[0]
	_screen.pick(false, {"grid": "backpack", "x": item["x"], "y": item["y"]})
