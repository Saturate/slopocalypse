class_name TraderScreen
extends CanvasLayer
## Client only, local player: the trade screen. Your gear on the left, each item tagged with
## what the trader pays for it; the goods in the middle as item tiles under category tabs,
## each tagged with its price; the details of whatever the mouse is on at the right. Click a
## good to buy it into the first free place, or drag it onto a place in your gear. Drag one
## of your items onto the goods (or right click or Ctrl+click it) to sell it. Every trade is
## a request the server decides and the screen redraws from its answer; a trade the screen
## can already tell would be refused (too few tokens, no room) is not sent, and it says why.
## Esc, Tab or F closes it.

const BG := UiPalette.BACKDROP
const ACCENT := UiPalette.ACCENT
const TEXT := UiPalette.TEXT
const DIM := UiPalette.DIM
const CELL := GearPanel.CELL
## The tab that lists every good.
const ALL := "all"
## Goods area in cells: room for the widest good (six cells) with a smaller one beside it.
const GOODS_CELLS := 9
## Height of the goods at the 1600x900 base: with the header, tabs and message line the
## panel still fits at 720p with room around it.
const STOCK_HEIGHT := 510.0
## Kept clear beside the tiles for the scroll bar, so it never covers a price tag.
const SCROLLBAR_ROOM := 16.0
const DETAIL_WIDTH := 300.0
## The detail picture's box: a six-cell gun at 50 px a cell, a one-cell item at most 110.
const PICTURE_SIZE := Vector2(300.0, 110.0)
## How far the mouse moves with a good held before it is a drag rather than a click.
const DRAG_START := 6.0
const DRAG_ALPHA := 0.9
## A good the player cannot pay for is drawn faded, its price greyed.
const UNAFFORDABLE_ALPHA := 0.7
const SELL_FILL := Color(UiPalette.ACCENT, 0.12)
const SELL_FILL_HOT := Color(UiPalette.ACCENT, 0.26)
const SELL_PLATE := Color(UiPalette.INK, 0.88)
## How long a good bought for a chosen place is waited for. A refused buy never arrives (the
## server tells only its own instance why), and an entry left behind would move the next item
## of that kind you pick up; a granted buy arrives within a round trip.
const PENDING_SECONDS := 5.0

var trader: Node
var peer := 0

var _root: Control
var _gear: GearPanel
var _tokens: Label
var _message: Label
var _overlay: Control
## The goods column (tabs and tiles): where your items are dropped to sell.
var _goods_box: Control
var _scroll: ScrollContainer
## The goods' grid: tiles placed by `_pack`, in `_order`.
var _shelf: Control
var _order: Array[String] = []
var _tab_buttons: Dictionary[String, Button] = {}
## Item id -> its tile among the goods.
var _tiles: Dictionary[String, Control] = {}
var _category := ALL
var _hover := ""
var _detail: Dictionary = {}
var _picture: Control
var _name: Label
var _about: Label
var _stats: GridContainer
var _price: Label
## A good pressed but not yet dragged: `{item, at, grab}`.
var _press: Dictionary = {}
## While dragging: `{good: item, grab}` for a good, `{uid, item, placed, grab}` for yours.
var _drag: Dictionary = {}
var _drag_rotated := false
## Where the mouse is on the screen, as its events last said: what is dragged is drawn here.
var _pointer := Vector2.ZERO
## Goods bought for a chosen place, oldest first, until each arrives:
## `{item, place, before: {uid: true}, left: seconds}`.
var _pending: Array[Dictionary] = []
## Item id -> the trader's offer as tag text, for the tags drawn on your gear every frame.
var _offers: Dictionary[String, String] = {}
var _shown_tokens := -1
## Set while drawing when an item's picture is not rendered yet, so it is drawn again.
var _icons_missing := false


func _ready() -> void:
	layer = UiLayers.TRADER
	_build_ui()
	_root.visible = false
	EventBus.subscribe(&"trader.opened", _on_opened)
	EventBus.subscribe(&"trader.refused", _on_refused)
	EventBus.subscribe(&"inventory.changed", _on_changed)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"trader.opened", _on_opened)
	EventBus.unsubscribe(&"trader.refused", _on_refused)
	EventBus.unsubscribe(&"inventory.changed", _on_changed)


func is_open() -> bool:
	return _root.visible


func open() -> void:
	_root.visible = true
	UiStack.push(self)
	say("")
	_hover = ""
	_detail = {}
	_fill_detail()
	_gear.refresh()
	_redraw_goods()


func close() -> void:
	_press = {}
	_pending.clear()
	_end_drag()
	_root.visible = false
	UiStack.pop(self)


func _inventory() -> Node:
	return get_tree().get_first_node_in_group(&"inventory_api")


func _missions() -> Node:
	return get_tree().get_first_node_in_group(&"missions_api")


func tokens() -> int:
	var missions := _missions()
	return int(missions.get(&"my_tokens")) if missions != null else 0


func can_afford(item: String) -> bool:
	return tokens() >= int(trader.call(&"price_of", item))


## The line under the panels: why a trade was refused, or empty.
func message() -> String:
	return _message.text


func say(text: String, colour: Color = TEXT) -> void:
	_message.text = text
	_message.add_theme_color_override(&"font_color", colour)


# --- Goods and tabs -------------------------------------------------------------------

## Shows the goods of one tab (`all`, or a category from the trader's `tabs`).
func set_category(category: String) -> void:
	_category = category
	for c: String in _tab_buttons:
		_tab_buttons[c].set_pressed_no_signal(c == category)
	for item: String in _tiles:
		_tiles[item].visible = category == ALL or tab_of(item) == category
	_pack()
	_scroll.scroll_vertical = 0


## Lays the shown goods into the grid as the inventory places things: each in turn at the
## first spot, row by row, where its w x h cells are free.
func _pack() -> void:
	var taken: Dictionary[Vector2i, bool] = {}
	var rows := 0
	for item in _order:
		var tile := _tiles[item]
		if not tile.visible:
			continue
		var size := _size_of(item)
		var at := _free_spot(taken, size)
		for y in size.y:
			for x in size.x:
				taken[at + Vector2i(x, y)] = true
		tile.position = Vector2(at * CELL)
		tile.size = Vector2(size * CELL)
		rows = maxi(rows, at.y + size.y)
	_shelf.custom_minimum_size = Vector2(GOODS_CELLS * CELL, rows * CELL)


static func _free_spot(taken: Dictionary[Vector2i, bool], size: Vector2i) -> Vector2i:
	var y := 0
	while true:
		for x in GOODS_CELLS - mini(size.x, GOODS_CELLS) + 1:
			var free := true
			for dy in size.y:
				for dx in size.x:
					if taken.has(Vector2i(x + dx, y + dy)):
						free = false
			if free:
				return Vector2i(x, y)
		y += 1
	return Vector2i.ZERO


func shown_category() -> String:
	return _category


## The goods the open tab shows, in the order they are laid out.
func shown_goods() -> Array[String]:
	var out: Array[String] = []
	for item in _order:
		if _tiles[item].visible:
			out.append(item)
	return out


## The tab a good sits under: its category from the item data when a tab has it, otherwise
## the last tab.
func tab_of(item: String) -> String:
	var inventory := _inventory()
	var category := str(inventory.call(&"item_category", item)) if inventory != null else ""
	var last := ""
	for tab: Dictionary in trader.call(&"tabs"):
		var c := str(tab["category"])
		if c == ALL:
			continue
		if c == category:
			return c
		last = c
	return last


func _size_of(item: String) -> Vector2i:
	var inventory := _inventory()
	var size: Array = (inventory.call(&"item_info", item) as Dictionary).get("size", [1, 1]) if inventory != null else [1, 1]
	return Vector2i(int(size[0]), int(size[1]))


func _name_of(item: String) -> String:
	var inventory := _inventory()
	var info: Dictionary = inventory.call(&"item_info", item) if inventory != null else {}
	return str(info.get("short", info.get("name", item)))


# --- Buying ---------------------------------------------------------------------------

## Buys `item` into the first free place, as a click on its tile does. False, saying why,
## when the screen can tell the trade would be refused.
func buy(item: String) -> bool:
	return _ask_buy(item, {})


## Buys `item` into `place` in your gear (`{slot}` or `{grid, x, y, rotated}`), as dropping
## its tile there does. The server puts what it sells in the first free place; once it
## arrives the screen moves it to `place` (see `_place_bought`).
func buy_at(item: String, place: Dictionary) -> bool:
	return _ask_buy(item, place)


## Why buying `item` (into `place`, or anywhere when empty) would be refused, or "".
func buy_refusal(item: String, place: Dictionary = {}) -> String:
	if not can_afford(item):
		return "Not enough tokens for the %s." % _name_of(item)
	var gear := _gear.gear()
	if gear == null:
		return ""
	if place.is_empty():
		if not _inventory().call(&"room_for", peer, item):
			return "No room in your gear for the %s." % _name_of(item)
	elif not gear.can_place(item, false, place, -1):
		return "The %s does not fit there." % _name_of(item)
	return ""


func _ask_buy(item: String, place: Dictionary) -> bool:
	var why := buy_refusal(item, place)
	if not why.is_empty():
		say(why, UiPalette.BAD)
		return false
	say("")
	# Set before asking: on the server's own instance the answer arrives within the call.
	if not place.is_empty():
		_pending.append({"item": item, "place": place.duplicate(), "before": _uids(), "left": PENDING_SECONDS})
	trader.call(&"request_buy", item)
	return true


## How many goods bought for a chosen place have not arrived yet.
func pending_buys() -> int:
	return _pending.size()


func _uids() -> Dictionary:
	var out := {}
	var gear := _gear.gear()
	if gear != null:
		for placed: Dictionary in gear.all_items():
			out[int(placed["uid"])] = true
	return out


## Goods bought for a chosen place that have arrived (an item of that kind that was not
## there when it was bought) move there if the place is still free; otherwise they stay
## where the server put them. Bought goods of one kind are alike, so the oldest buy takes the
## lowest new uid (the server numbers what it gives in order).
func _place_bought() -> void:
	var gear := _gear.gear()
	if _pending.is_empty() or gear == null:
		return
	var items := gear.all_items()
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["uid"]) < int(b["uid"]))
	var moves: Array[Array] = []
	var i := 0
	while i < _pending.size():
		var entry := _pending[i]
		var uid := _new_uid(items, entry)
		if uid < 0:
			i += 1
			continue
		_pending.remove_at(i)
		for other in _pending:
			(other["before"] as Dictionary)[uid] = true
		var place: Dictionary = entry["place"]
		if gear.can_place(str(entry["item"]), false, place, uid):
			moves.append([uid, place])
	# Asked after the loop: on the server's own instance each move answers within the call.
	for move in moves:
		_inventory().call(&"request_move", int(move[0]), move[1])


static func _new_uid(items: Array, entry: Dictionary) -> int:
	var before: Dictionary = entry["before"]
	for placed: Dictionary in items:
		if str(placed["item"]) == str(entry["item"]) and not before.has(int(placed["uid"])):
			return int(placed["uid"])
	return -1


# --- Selling --------------------------------------------------------------------------

## Sells the item at a place in your gear (`{slot}` or `{grid, x, y}`), as Ctrl+click does.
func sell_at(place: Dictionary) -> bool:
	var placed := _gear.item_at(place)
	if placed.is_empty():
		return false
	trader.call(&"request_sell", int(placed["uid"]))
	return true


## Picks up your item at `place` to drag it onto the goods, as a mouse press on it does.
func pick_mine(place: Dictionary) -> bool:
	var placed := _gear.item_at(place)
	if placed.is_empty():
		return false
	var grab := Vector2(0.5, 0.5)
	if place.has("grid"):
		grab += Vector2(int(place.get("x", 0)) - int(placed["x"]), int(place.get("y", 0)) - int(placed["y"]))
	_drag = {"uid": int(placed["uid"]), "item": str(placed["item"]), "placed": placed, "grab": grab}
	_gear.skip_uid = int(placed["uid"])
	_gear.refresh()
	return true


## Lets go of your dragged item over the goods: sells it.
func drop_to_sell() -> bool:
	if not _drag.has("uid"):
		return false
	var uid := int(_drag["uid"])
	_end_drag()
	trader.call(&"request_sell", uid)
	return true


func _end_drag() -> void:
	_drag = {}
	_drag_rotated = false
	_gear.skip_uid = -1
	_gear.refresh()
	_overlay.queue_redraw()


# --- Details --------------------------------------------------------------------------

## What the detail panel shows for `item`: `{item, name, about, stats: [{label, value}],
## price, selling}`. `selling` is for your own item (the price is the trader's offer);
## otherwise the price is what the stall asks.
func detail_of(item: String, selling: bool) -> Dictionary:
	var inventory := _inventory()
	var info: Dictionary = inventory.call(&"item_info", item) if inventory != null else {}
	var stats: Array = inventory.call(&"item_stats", item) if inventory != null else []
	return {
		"item": item,
		"name": str(info.get("name", item)),
		"about": str(info.get("about", "")),
		"stats": stats,
		"price": int(trader.call(&"sell_price" if selling else &"price_of", item)),
		"selling": selling,
	}


func show_detail(item: String, selling: bool) -> void:
	if str(_detail.get("item", "")) == item and bool(_detail.get("selling", false)) == selling:
		return
	_detail = detail_of(item, selling)
	_fill_detail()


func detail() -> Dictionary:
	return _detail


func _fill_detail() -> void:
	for child in _stats.get_children():
		_stats.remove_child(child)
		child.queue_free()
	_picture.queue_redraw()
	_picture.visible = not _detail.is_empty()
	if _detail.is_empty():
		_name.text = ""
		_about.text = "Point at an item to see what it does."
		_price.text = ""
		return
	_name.text = str(_detail["name"])
	_about.text = str(_detail["about"])
	for row: Dictionary in _detail["stats"]:
		_stats.add_child(_label(str(row["label"]), 17, DIM))
		_stats.add_child(_label(str(row["value"]), 17, TEXT))
	var price := int(_detail["price"])
	if bool(_detail["selling"]):
		_price.text = "Trader pays %d tokens" % price
		_price.add_theme_color_override(&"font_color", UiPalette.GOOD)
	elif can_afford(str(_detail["item"])):
		_price.text = "Costs %d tokens" % price
		_price.add_theme_color_override(&"font_color", ACCENT)
	else:
		_price.text = "Costs %d tokens (you have %d)" % [price, tokens()]
		_price.add_theme_color_override(&"font_color", UiPalette.BAD)


# --- Events and input -----------------------------------------------------------------

func _on_opened(p: Dictionary) -> void:
	if int(p.get("peer", -1)) == peer:
		open()


## Only reaches a screen on the server's own instance; elsewhere the screen's own checks
## catch what they can.
func _on_refused(p: Dictionary) -> void:
	if int(p.get("peer", -1)) == peer and is_open():
		say("The trader refused: %s." % str(p.get("reason", "")), UiPalette.BAD)


func _on_changed(p: Dictionary) -> void:
	if int(p.get("peer", -1)) != peer:
		return
	_place_bought()
	if is_open():
		_gear.refresh()


func _process(delta: float) -> void:
	if not is_open():
		return
	var prof := Prof.start()
	for entry in _pending:
		entry["left"] = float(entry["left"]) - delta
	_pending = _pending.filter(func(e: Dictionary) -> bool: return float(e["left"]) > 0.0)
	var now := tokens()
	if now != _shown_tokens:
		_shown_tokens = now
		_tokens.text = "Tokens: %d" % now
		_redraw_goods()
		_fill_detail()
	if _icons_missing:
		_icons_missing = false
		_redraw_goods()
		_picture.queue_redraw()
	_gear.refresh()
	if not _drag.is_empty():
		_overlay.queue_redraw()
	Prof.stop(&"trader/screen", prof)


func _redraw_goods() -> void:
	for tile: Control in _tiles.values():
		tile.queue_redraw()


func _input(event: InputEvent) -> void:
	if not UiStack.is_top(self):
		return
	if event.is_action_pressed(&"interact") or event.is_action_pressed(&"inventory") or UiStack.is_cancel(event):
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.is_pressed() and not event.is_echo():
		if (event as InputEventKey).keycode == KEY_R and _drag.has("good"):
			_drag_rotated = not _drag_rotated
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_press_at(mb)
		elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_release_at(mb.global_position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and _drag.is_empty():
			var place := _place_at(mb.global_position)
			if not place.is_empty():
				sell_at(place)
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		_move_to((event as InputEventMouseMotion).global_position)


func _press_at(mb: InputEventMouseButton) -> void:
	var good := good_at(mb.global_position)
	if not good.is_empty():
		var tile := _tiles[good]
		var local := tile.get_global_transform().affine_inverse() * mb.global_position
		_press = {"item": good, "at": mb.global_position, "grab": (local / CELL).floor() + Vector2(0.5, 0.5)}
		get_viewport().set_input_as_handled()
		return
	var place := _place_at(mb.global_position)
	if place.is_empty():
		return
	if mb.ctrl_pressed:
		sell_at(place)
	else:
		pick_mine(place)
	get_viewport().set_input_as_handled()


func _release_at(global: Vector2) -> void:
	if _drag.has("good"):
		var place := _drop_place(global)
		var item := str(_drag["good"])
		_end_drag()
		if not place.is_empty():
			buy_at(item, place)
		get_viewport().set_input_as_handled()
	elif _drag.has("uid"):
		if _goods_box.get_global_rect().has_point(global):
			drop_to_sell()
		else:
			_end_drag()
		get_viewport().set_input_as_handled()
	elif not _press.is_empty():
		var item := str(_press["item"])
		_press = {}
		buy(item)
		get_viewport().set_input_as_handled()


## The mouse moved to `global`: a held good becomes a drag once it has moved far enough,
## a drag follows, and otherwise whatever is under it fills the details.
func _move_to(global: Vector2) -> void:
	_pointer = global
	if not _press.is_empty() and global.distance_to(_press["at"]) > DRAG_START:
		_drag = {"good": _press["item"], "grab": _press["grab"]}
		_drag_rotated = false
		_press = {}
	if not _drag.is_empty():
		_overlay.queue_redraw()
		return
	var good := good_at(global)
	if good != _hover:
		_hover = good
		_redraw_goods()
	if not good.is_empty():
		show_detail(good, false)
		return
	var place := _place_at(global)
	var placed := _gear.item_at(place) if not place.is_empty() else {}
	if not placed.is_empty():
		show_detail(str(placed["item"]), true)


## The good whose tile is under `global` (and not scrolled out of sight), or "".
func good_at(global: Vector2) -> String:
	if not _scroll.get_global_rect().has_point(global):
		return ""
	for item: String in _tiles:
		var tile := _tiles[item]
		if tile.visible and tile.get_global_rect().has_point(global):
			return item
	return ""


## Your gear's slot or cell under `global`: `{slot}` or `{grid, x, y}`, or empty.
func _place_at(global: Vector2) -> Dictionary:
	var t := _gear.target_at(global)
	if t.has("slot"):
		return {"slot": t["slot"]}
	if t.has("grid"):
		var cell: Vector2i = t["cell"]
		return {"grid": t["grid"], "x": cell.x, "y": cell.y}
	return {}


## Where a dragged good would land in your gear with the mouse at `global`: a slot, or the
## grid cell of its top left corner (from where its tile was grabbed).
func _drop_place(global: Vector2) -> Dictionary:
	var t := _gear.target_at(global)
	if t.has("slot"):
		return {"slot": t["slot"]}
	if not t.has("grid"):
		return {}
	var local: Vector2 = t["local"]
	var top := local - (_grab() - Vector2(0.5, 0.5)) * CELL
	return {"grid": t["grid"], "x": floori(top.x / CELL), "y": floori(top.y / CELL), "rotated": _drag_rotated}


## Where in the dragged thing the mouse holds it, in cells; a good turned with R is held at
## the same spot of its turned shape.
func _grab() -> Vector2:
	var grab: Vector2 = _drag.get("grab", Vector2(0.5, 0.5))
	return Vector2(grab.y, grab.x) if _drag_rotated else grab


# --- Drawing --------------------------------------------------------------------------

func _draw_good(tile: Control, item: String) -> void:
	var inventory := _inventory()
	if inventory == null:
		return
	var size := _size_of(item)
	var afford := can_afford(item)
	if not afford:
		# A solid backing, so a faded tile still reads as a tile rather than a hole.
		tile.draw_rect(Rect2(Vector2.ONE * GridPainter.GAP, Vector2(size * CELL) - Vector2.ONE * GridPainter.GAP * 2), UiPalette.STEEL_SUNK)
	GridPainter.draw_tile(tile, inventory, {"item": item}, Vector2.ZERO, size.x, size.y, CELL, 1.0 if afford else UNAFFORDABLE_ALPHA)
	var price := str(int(trader.call(&"price_of", item)))
	GridPainter.draw_tag(tile, Vector2.ZERO, size.x, size.y, CELL, price, ACCENT if afford else Color(DIM, 0.6))
	if item == _hover:
		tile.draw_rect(Rect2(Vector2.ZERO, tile.size).grow(-GridPainter.GAP), ACCENT, false, 2.0)
	if inventory.call(&"item_icon_pending", item):
		_icons_missing = true


func _draw_picture() -> void:
	var inventory := _inventory()
	if _detail.is_empty() or inventory == null:
		return
	var item := str(_detail["item"])
	var size := _size_of(item)
	var cell := mini(int(PICTURE_SIZE.x / size.x), int(PICTURE_SIZE.y / size.y))
	# Left aligned like the text under it.
	var at := Vector2(0.0, (PICTURE_SIZE.y - size.y * cell) / 2.0)
	GridPainter.draw_tile(_picture, inventory, {"item": item}, at, size.x, size.y, cell, 1.0)
	if inventory.call(&"item_icon_pending", item):
		_icons_missing = true


## The dragged thing under the mouse. A good over your gear shows a green or red block
## where it would land; your own item lights up the goods as the place to sell it.
func _draw_overlay() -> void:
	if _drag.is_empty():
		return
	var inventory := _inventory()
	if inventory == null:
		return
	var global := _pointer
	var mouse := global - _overlay.get_global_rect().position
	var grab := _grab()
	if _drag.has("uid"):
		var box := Rect2(_goods_box.get_global_rect().position - _overlay.get_global_rect().position, _goods_box.size)
		var hot := _goods_box.get_global_rect().has_point(global)
		_overlay.draw_rect(box, SELL_FILL_HOT if hot else SELL_FILL)
		_overlay.draw_rect(box, ACCENT, false, 2.0)
		var font := _overlay.get_theme_default_font()
		var text := "Sell for %d tokens" % int(trader.call(&"sell_price", str(_drag["item"])))
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiPalette.HEADING)
		# On a dark plate at the top of the goods: over the pictures the words would get lost.
		var plate := Rect2(Vector2(box.get_center().x - text_size.x / 2.0, box.position.y + box.size.y * 0.25) - Vector2(12.0, 6.0), text_size + Vector2(24.0, 12.0))
		_overlay.draw_rect(plate, SELL_PLATE)
		_overlay.draw_rect(plate, ACCENT, false, 2.0)
		_overlay.draw_string(font, plate.position + Vector2(12.0, 6.0 + font.get_ascent(UiPalette.HEADING)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiPalette.HEADING, ACCENT)
		var placed: Dictionary = _drag["placed"]
		GridPainter.draw_tile(_overlay, inventory, placed, mouse - grab * CELL, int(placed["w"]), int(placed["h"]), CELL, DRAG_ALPHA)
		return
	var item := str(_drag["good"])
	var size := _size_of(item)
	if _drag_rotated:
		size = Vector2i(size.y, size.x)
	GridPainter.draw_tile(_overlay, inventory, {"item": item, "rotated": _drag_rotated}, mouse - grab * CELL, size.x, size.y, CELL, DRAG_ALPHA)
	# The landing block over the dragged tile: under it, the tile hid it.
	var place := _drop_place(global)
	var gear := _gear.gear()
	var view := _gear.view_of(place) if not place.is_empty() else null
	if gear != null and view != null:
		var origin := view.get_global_rect().position - _overlay.get_global_rect().position
		var block := Rect2(origin, view.size)
		if place.has("grid"):
			block = Rect2(origin + Vector2(int(place["x"]), int(place["y"])) * CELL, Vector2(size) * CELL)
		var fits := can_afford(item) and gear.can_place(item, false, place, -1)
		var colour := GridPainter.OK if fits else GridPainter.BAD
		_overlay.draw_rect(block, colour)
		_overlay.draw_rect(block, Color(colour.lightened(0.4), 1.0), false, 3.0)


# --- Layout ---------------------------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = BG
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := PanelContainer.new()
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
	col.add_child(_label("Click or drag a good to buy  ·  Drag your item onto the goods, right click or Ctrl+click it to sell  ·  Esc closes", 14, DIM))
	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation", 28)
	col.add_child(sides)
	var mine := VBoxContainer.new()
	sides.add_child(mine)
	mine.add_child(_label("YOU", 22, ACCENT))
	mine.add_child(_label("Green tags: what the trader pays", 14, UiPalette.GOOD))
	_gear = GearPanel.new()
	_gear.inventory = _inventory()
	_gear.gear_source = func() -> InventoryGear: return _inventory().call(&"grid_of", peer)
	_gear.tag_for = func(placed: Dictionary) -> Array: return [_offer_of(str(placed["item"])), UiPalette.GOOD]
	mine.add_child(_gear)
	_build_goods(sides)
	_build_detail(sides)
	_message = _label("", 17, TEXT)
	_message.custom_minimum_size.y = 24
	col.add_child(_message)
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	_root.add_child(_overlay)
	set_category(ALL)
	_fill_detail()


func _build_goods(sides: HBoxContainer) -> void:
	var theirs := VBoxContainer.new()
	theirs.add_theme_constant_override("separation", 6)
	sides.add_child(theirs)
	_goods_box = theirs
	theirs.add_child(_label("FOR SALE", 22, ACCENT))
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	theirs.add_child(tabs)
	var group := ButtonGroup.new()
	for tab: Dictionary in trader.call(&"tabs"):
		var c := str(tab["category"])
		var b := Button.new()
		b.text = str(tab["label"])
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", UiPalette.HINT)
		# The open tab in the accent colour, so which one is showing reads at a glance.
		b.add_theme_stylebox_override(&"pressed", _tab_style(b))
		b.add_theme_stylebox_override(&"hover_pressed", _tab_style(b))
		b.add_theme_color_override(&"font_pressed_color", UiPalette.INK)
		b.add_theme_color_override(&"font_hover_pressed_color", UiPalette.INK)
		b.pressed.connect(set_category.bind(c))
		tabs.add_child(b)
		_tab_buttons[c] = b
	# The goods scroll in a box of fixed size, so a long list never runs off the window.
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(GOODS_CELLS * CELL + SCROLLBAR_ROOM, STOCK_HEIGHT)
	theirs.add_child(_scroll)
	_shelf = Control.new()
	_shelf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_shelf)
	_order = _goods_in_order()
	for item in _order:
		var size := _size_of(item)
		var tile := Control.new()
		tile.custom_minimum_size = Vector2(size * CELL)
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.draw.connect(_draw_good.bind(tile, item))
		_shelf.add_child(tile)
		_tiles[item] = tile


## The stock grouped by tab, and within a tab the tallest and widest first, so the small
## goods fill the gaps beside them; otherwise in the trader's order.
func _goods_in_order() -> Array[String]:
	var rank := {}
	var i := 0
	for tab: Dictionary in trader.call(&"tabs"):
		rank[str(tab["category"])] = i
		i += 1
	var keyed: Array[Array] = []
	var n := 0
	for entry: Dictionary in trader.call(&"stock"):
		var item := str(entry["item"])
		keyed.append([int(rank.get(tab_of(item), i)), -_size_of(item).y, -_size_of(item).x, n, item])
		n += 1
	keyed.sort_custom(func(a: Array, b: Array) -> bool:
		for k in 4:
			if int(a[k]) != int(b[k]):
				return int(a[k]) < int(b[k])
		return false)
	var out: Array[String] = []
	for k: Array in keyed:
		out.append(str(k[4]))
	return out


func _build_detail(sides: HBoxContainer) -> void:
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = DETAIL_WIDTH
	box.add_theme_constant_override("separation", 8)
	sides.add_child(box)
	box.add_child(_label("DETAILS", 22, ACCENT))
	_picture = Control.new()
	_picture.custom_minimum_size = PICTURE_SIZE
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture.draw.connect(_draw_picture)
	box.add_child(_picture)
	_name = _label("", 20, TEXT)
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name.custom_minimum_size.x = DETAIL_WIDTH
	box.add_child(_name)
	_about = _label("", 17, DIM)
	_about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_about.custom_minimum_size.x = DETAIL_WIDTH
	box.add_child(_about)
	_stats = GridContainer.new()
	_stats.columns = 2
	_stats.add_theme_constant_override("h_separation", 16)
	box.add_child(_stats)
	_price = _label("", 20, ACCENT)
	box.add_child(_price)


## The theme's pressed button, filled with the accent colour.
static func _tab_style(b: Button) -> StyleBox:
	var style: StyleBox = b.get_theme_stylebox(&"pressed").duplicate()
	if style is SteelPlate:
		(style as SteelPlate).fill = ACCENT
	return style


func _offer_of(item: String) -> String:
	if not _offers.has(item):
		_offers[item] = str(int(trader.call(&"sell_price", item)))
	return _offers[item]


func _label(text: String, size: int, colour: Color) -> Label:
	return UiText.label(text, size, colour)
