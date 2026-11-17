extends Node
## Capture setup: the title screen over the live city, as boot puts them together.

const BACKDROP := "res://modules/city/title/title_backdrop.gd"


func _ready() -> void:
	var menu := MainMenu.new()
	menu.servers = ServerList.new()
	menu.profile_path = "user://capture_profile.json"
	menu.has_range = true
	menu.has_library = true
	var backdrop: Node = (load(BACKDROP) as GDScript).new()
	backdrop.connect(&"shown", menu.show_world)
	add_child(backdrop)
	add_child(menu)
