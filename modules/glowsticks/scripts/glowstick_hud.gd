class_name GlowstickHud
extends CanvasLayer
## Client, local player: how many glowsticks you carry and the key to crack one, or the time
## left on the lit one with the keys to stow or show and to drop it. Hidden when you have
## none, so it says nothing about a stick until you find one.

var view: GlowstickView
var player: Node3D

var _row: HBoxContainer
var _main: KeyHint
var _drop: KeyHint


func _ready() -> void:
	layer = UiLayers.PROMPTS
	_row = HBoxContainer.new()
	_row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	# Just over the medkit and charge counts.
	_row.position += Vector2(32, -132)
	_row.add_theme_constant_override(&"separation", 18)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)
	_main = KeyHint.new(&"glowstick")
	_drop = KeyHint.new(&"glowstick_drop", "Drop")
	_row.add_child(_main)
	_row.add_child(_drop)


func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		_row.visible = false
		return
	var peer := int(player.get_meta(&"peer_id", multiplayer.get_unique_id()))
	var inventory := get_tree().get_first_node_in_group(&"inventory_api")
	var spare := int(inventory.call(&"count", peer, GlowstickRules.ITEM)) if inventory != null else 0
	var lit := view.lit_of(peer)
	if not lit.is_empty():
		var left := ceili(float(lit["left"]))
		var clock := "%d:%02d" % [floori(left / 60.0), left % 60]
		_main.text = ("Glowstick %s, stow" % clock) if bool(lit["shown"]) else ("Glowstick %s (stowed), show" % clock)
	else:
		_main.text = "Glowstick x%d, crack" % spare
	_drop.visible = not lit.is_empty()
	_row.visible = (spare > 0 or not lit.is_empty()) and not UiStack.is_blocking()
