class_name LootPrompt
extends CanvasLayer
## Client only, local player: "E  Pick up <item>" under the crosshair while loot is in
## reach, using the same reach rule the server uses for the pickup.

var inventory: Node
var player: Node3D
var peer := 1

var _label: Label
var _meds: Label


func _ready() -> void:
	layer = 4
	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_label.position += Vector2(-120, 40)
	_label.custom_minimum_size = Vector2(240, 24)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override(&"font_size", 17)
	_label.add_theme_color_override(&"font_color", Color(0.95, 0.93, 0.85))
	_label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override(&"outline_size", 6)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_meds = Label.new()
	_meds.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_meds.position += Vector2(32, -96)
	_meds.add_theme_font_size_override(&"font_size", 15)
	_meds.add_theme_color_override(&"font_color", Color(0.9, 0.75, 0.72))
	_meds.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_meds)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"use_medkit") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		inventory.call(&"request_use", "medkit")
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		queue_free()
		return
	var loot: Node = inventory.call(&"loot_in_reach", player)
	var crate: Node = inventory.call(&"crate_in_reach", player) if loot == null else null
	_label.visible = (loot != null or crate != null) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if loot != null:
		var info: Dictionary = inventory.call(&"item_info", str(loot.get(&"item")))
		_label.text = "E   Pick up %s" % str(info.get("name", loot.get(&"item")))
	elif crate != null:
		_label.text = "Empty crate" if crate.get_meta(&"empty", false) else "E   Search crate"
	# Medkits: how many, and the key, just above the health bar.
	_meds.text = "H   Medkit x%d" % int(inventory.call(&"count", peer, "medkit"))
	_meds.visible = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
