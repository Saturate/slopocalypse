extends Node
## Capture setup: the title screen as a player sees it after a failed join, with every
## button showing.


func _ready() -> void:
	var menu := MainMenu.new()
	menu.servers = ServerList.new()
	menu.profile_path = "user://capture_profile.json"
	for a in ["friends.example.net", "100.88.12.40:7777", "192.168.1.20"]:
		menu.servers.remember(a)
	menu.message = "Could not reach 100.88.12.40:7777."
	menu.has_range = true
	menu.has_library = true
	add_child(menu)
