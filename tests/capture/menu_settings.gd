extends Node
## Capture setup: the settings screen over the title, with the player's keys registered as
## they are in a session.

const PLAYER_DATA := "res://modules/player/data/player.json"


func _ready() -> void:
	if ResourceLoader.exists(PLAYER_DATA) or FileAccess.file_exists(PLAYER_DATA):
		var data: Dictionary = Data.load_json(PLAYER_DATA)
		InputBindings.register(data.get("bindings", {}), &"capture")
	var menu := MainMenu.new()
	menu.servers = ServerList.new()
	menu.profile_path = "user://capture_profile.json"
	add_child(menu)
	menu.open_settings()
