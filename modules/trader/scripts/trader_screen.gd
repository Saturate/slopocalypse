class_name TraderScreen
extends CanvasLayer
## Client only, local player: the trade screen. Your gear on the left (Ctrl+click or right
## click an item to sell it), the trader's stock on the right (click to buy), your tokens on
## top. Every trade is a request the server decides; the screen redraws from its answer.
## Esc, Tab or F closes it.

const BG := Color(0.05, 0.06, 0.06, 0.82)
const PANEL := Color(0.11, 0.12, 0.11, 0.97)
const ACCENT := Color(0.82, 0.62, 0.3)
const TEXT := Color(0.88, 0.88, 0.84)
const DIM := Color(0.66, 0.67, 0.63)
const STOCK_COLUMNS := 3

var trader: Node
var peer := 0

var _root: Control
var _gear: GearPanel
var _tokens: Label
var _info: Label
var _stock: GridContainer


func _ready() -> void:
	layer = 43
	_build_ui()
	_root.visible = false
	EventBus.subscribe(&"trader.opened", _on_opened)
	EventBus.subscribe(&"inventory.changed", _on_changed)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"trader.opened", _on_opened)
	EventBus.unsubscribe(&"inventory.changed", _on_changed)


func is_open() -> bool:
	return _root.visible


func open() -> void:
	_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_gear.refresh()


func close() -> void:
	_root.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _inventory() -> Node:
	return get_tree().get_first_node_in_group(&"inventory_api")


func _missions() -> Node:
	return get_tree().get_first_node_in_group(&"missions_api")


func buy(item: String) -> void:
	trader.call(&"request_buy", item)


## Sells the item at a place in your gear (`{slot}` or `{grid, x, y}`), as Ctrl+click does.
func sell_at(place: Dictionary) -> bool:
	var placed := _gear.item_at(place)
	if placed.is_empty():
		return false
	trader.call(&"request_sell", int(placed["uid"]))
	return true


func _on_opened(p: Dictionary) -> void:
	if int(p.get("peer", -1)) == peer:
		open()


func _on_changed(p: Dictionary) -> void:
	if int(p.get("peer", -1)) == peer and is_open():
		_gear.refresh()


func _process(_delta: float) -> void:
	if not is_open():
		return
	var missions := _missions()
	_tokens.text = "Tokens: %d" % int(missions.get(&"my_tokens")) if missions != null else ""
	_gear.refresh()


func _input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action_pressed(&"interact") or event.is_action_pressed(&"inventory"):
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.is_pressed():
		var mb := event as InputEventMouseButton
		var selling := mb.button_index == MOUSE_BUTTON_RIGHT or (mb.button_index == MOUSE_BUTTON_LEFT and mb.ctrl_pressed)
		var place := _place_at(mb.global_position)
		if selling and not place.is_empty():
			sell_at(place)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var place := _place_at((event as InputEventMouseMotion).global_position)
		var placed := _gear.item_at(place) if not place.is_empty() else {}
		if placed.is_empty():
			return
		var info: Dictionary = _inventory().call(&"item_info", str(placed["item"]))
		_info.text = "%s  ·  sells for %d tokens (Ctrl+click or right click)" % [info.get("name", placed["item"]), int(trader.call(&"sell_price", str(placed["item"])))]


func _place_at(global: Vector2) -> Dictionary:
	var t := _gear.target_at(global)
	if t.has("slot"):
		return {"slot": t["slot"]}
	if t.has("grid"):
		var cell: Vector2i = t["cell"]
		return {"grid": t["grid"], "x": cell.x, "y": cell.y}
	return {}


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = BG
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = ACCENT.darkened(0.5)
	style.border_width_top = 3
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	head.add_child(_label("TRADER", 26, ACCENT))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	_tokens = _label("", 20, TEXT)
	head.add_child(_tokens)
	col.add_child(_label("Click to buy  ·  Ctrl+click or right click your gear to sell  ·  Esc closes", 14, DIM))
	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation", 36)
	col.add_child(sides)
	var mine := VBoxContainer.new()
	sides.add_child(mine)
	mine.add_child(_label("YOU", 22, ACCENT))
	_gear = GearPanel.new()
	_gear.inventory = _inventory()
	_gear.gear_source = func() -> InventoryGear: return _inventory().call(&"grid_of", peer)
	mine.add_child(_gear)
	var theirs := VBoxContainer.new()
	sides.add_child(theirs)
	theirs.add_child(_label("FOR SALE", 22, ACCENT))
	_stock = GridContainer.new()
	_stock.columns = STOCK_COLUMNS
	_stock.add_theme_constant_override("h_separation", 6)
	_stock.add_theme_constant_override("v_separation", 6)
	theirs.add_child(_stock)
	var inventory := _inventory()
	for entry: Dictionary in trader.call(&"stock"):
		var item := str(entry["item"])
		var info: Dictionary = inventory.call(&"item_info", item) if inventory != null else {}
		var b := Button.new()
		b.text = "%s\n%d tokens" % [info.get("short", info.get("name", item)), int(entry["price"])]
		b.tooltip_text = str(info.get("name", item))
		b.custom_minimum_size = Vector2(130, 46)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(buy.bind(item))
		_stock.add_child(b)
	_info = _label("", 15, TEXT)
	_info.custom_minimum_size.y = 22
	col.add_child(_info)


func _label(text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	return l
