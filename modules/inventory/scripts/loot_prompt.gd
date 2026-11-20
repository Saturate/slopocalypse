class_name LootPrompt
extends CanvasLayer
## Client only, local player: "Pick up <item>" (or "Search body", "Search crate") with the
## interact key, on the prompt stack while it is in reach, using the same reach rule the
## server uses for the pickup. Also the medkit and charge counts with their keys.

var inventory: Node
var player: Node3D
var peer := 1

var _meds: KeyHint
var _charges: KeyHint
var _set_off: KeyHint
var _row: HBoxContainer


func _ready() -> void:
	layer = UiLayers.PROMPTS
	# Medkits and charges: how many, and their keys, just above the health bar.
	_row = HBoxContainer.new()
	_row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_row.position += Vector2(32, -96)
	_row.add_theme_constant_override(&"separation", 18)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)
	_meds = KeyHint.new(&"use_medkit")
	_charges = KeyHint.new(&"charge")
	_set_off = KeyHint.new(&"detonate", "Set off")
	for hint: KeyHint in [_meds, _charges, _set_off]:
		_row.add_child(hint)


func _exit_tree() -> void:
	PromptStack.of(get_tree()).clear_line(&"loot")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"use_medkit") and not UiStack.is_blocking():
		inventory.call(&"request_use", "medkit")
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		queue_free()
		return
	var prompts := PromptStack.of(get_tree())
	var loot: Node = inventory.call(&"loot_in_reach", player)
	var crate: Node = inventory.call(&"container_in_reach", player) if loot == null else null
	# What a press of interact will name to the server (the server can't see this machine's
	# ragdolls, #407).
	var intent := (player as PlayerController).intent() if player is PlayerController else null
	if intent != null:
		var shown: Node = loot if loot != null else crate
		intent.interact_target = shown.get_path() if shown != null else NodePath()
	if loot != null:
		var info: Dictionary = inventory.call(&"item_info", str(loot.get(&"item")))
		prompts.set_line(&"loot", &"interact", "Pick up %s" % str(info.get("name", loot.get(&"item"))))
	elif crate != null:
		var what := "body" if crate is LootBody else "crate"
		prompts.set_line(&"loot", &"interact", "Search %s%s" % [what, " (empty)" if crate.get_meta(&"empty", false) else ""])
	else:
		prompts.clear_line(&"loot")
	_meds.text = "Medkit x%d" % int(inventory.call(&"count", peer, "medkit"))
	var charges := int(inventory.call(&"count", peer, "breach_charge"))
	_charges.text = "Charge x%d" % charges
	_charges.visible = charges > 0
	_set_off.visible = charges > 0
	_row.visible = not UiStack.is_blocking()
