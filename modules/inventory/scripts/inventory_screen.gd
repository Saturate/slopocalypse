class_name InventoryScreen
extends GearScreen
## Client only, local player: your gear (Tab): slots, pockets, rig and backpack. See
## `GearScreen` for dragging; drag out to drop, right click uses.


func _ready() -> void:
	super._ready()
	layer = 40


func _hint() -> String:
	return "Drag to move  ·  R turns  ·  drag out to drop  ·  right click uses  ·  B mods your gun"


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"inventory"):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if is_open():
		close()
	else:
		open()


func close() -> void:
	_hide()
