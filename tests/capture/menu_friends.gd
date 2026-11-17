extends Node
## Capture setup: the "Play with friends" screen open over the title, with saved servers.


func _ready() -> void:
	var menu := MainMenu.new()
	menu.servers = ServerList.new()
	menu.profile_path = "user://capture_profile.json"
	for a in ["friends.example.net", "100.88.12.40:7777", "192.168.1.20"]:
		menu.servers.remember(a)
	add_child(menu)
	menu.open_friends()
