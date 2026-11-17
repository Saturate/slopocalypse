extends Node
## Capture setup: the credits screen open over the title.


func _ready() -> void:
	var menu := MainMenu.new()
	menu.servers = ServerList.new()
	menu.profile_path = "user://capture_profile.json"
	add_child(menu)
	menu.open_credits()
