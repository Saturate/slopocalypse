extends Node
## Capture setup: the main menu after a join that could not reach the server (#414).


func _ready() -> void:
	var menu := MainMenu.new()
	menu.message = Net.join_help("203.0.113.5", 7777)
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(menu)
