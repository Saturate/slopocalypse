class_name LootScreen
extends GearScreen
## Client only, local player: the loot screen for a body or crate, your gear on the left and
## theirs on the right, laid out the same way (slots, then grids). See `GearScreen` for
## dragging; Ctrl+click sends an item across, "Take all" empties the other side as far as
## it fits. Esc, Tab or F closes it.


func _two_sided() -> bool:
	return true


func _hint() -> String:
	return "Drag to move  ·  R turns  ·  Ctrl+click sends across  ·  drag out to drop  ·  Esc closes"


func _ready() -> void:
	super._ready()
	# Over the inventory screen and the HUD.
	layer = 41
	EventBus.subscribe(&"inventory.loot_changed", _on_loot_changed)
	EventBus.subscribe(&"inventory.loot_closed", _on_loot_closed)


func _exit_tree() -> void:
	super._exit_tree()
	EventBus.unsubscribe(&"inventory.loot_changed", _on_loot_changed)
	EventBus.unsubscribe(&"inventory.loot_closed", _on_loot_closed)


## Closes the screen and tells the server.
func close() -> void:
	if not is_open():
		return
	_hide()
	inventory.call(&"request_close_loot")


func _close_requested() -> void:
	close()


func _input(event: InputEvent) -> void:
	if is_open() and (event.is_action_pressed(&"inventory") or event.is_action_pressed(&"interact")):
		close()
		get_viewport().set_input_as_handled()
		return
	super._input(event)


func _on_loot_changed(p: Dictionary) -> void:
	if int(p.get("peer", -1)) != peer:
		return
	_titles[1].text = str(inventory.call(&"loot_title"))
	# A drag of an item someone else just took ends here.
	if not _dragging.is_empty() and bool(_dragging["theirs"]):
		var gear := _gear(true)
		var uid := int(_dragging["placed"]["uid"])
		if gear == null or not gear.all_items().any(func(i: Dictionary) -> bool: return int(i["uid"]) == uid):
			_dragging = {}
	if bool(p.get("opened", false)):
		open()
	_refresh()


func _on_loot_closed(p: Dictionary) -> void:
	if int(p.get("peer", -1)) == peer and is_open():
		_hide()
