extends Node
## Capture setup: the main menu as a player sees it after a failed join, with saved servers.


func _ready() -> void:
	var menu := MainMenu.new()
	menu.servers = ServerList.new()
	for a in ["friends.example.net", "100.88.12.40:7777", "192.168.1.20"]:
		menu.servers.remember(a)
	menu.message = "Could not reach 100.88.12.40:7777."
	add_child(menu)
