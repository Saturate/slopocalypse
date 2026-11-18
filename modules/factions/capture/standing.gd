extends Node3D
## Capture setup: the standing screen over the city, with one faction friendly, one neutral
## and one hostile.

const STREET := "res://modules/city/capture/street.gd"
const FACTIONS := "res://modules/factions/factions_module.gd"


func _ready() -> void:
	if ResourceLoader.exists(STREET):
		var street: Node = (load(STREET) as GDScript).new()
		add_child(street)
		street.set_process(false)
	var factions: Node = (load(FACTIONS) as GDScript).new()
	add_child(factions)
	factions.set(&"my_standing", {"militia": -64.0, "regulars": 12.0, "scavengers": 41.0})
	(factions.get_node(^"StandingScreen") as StandingScreen).open()
