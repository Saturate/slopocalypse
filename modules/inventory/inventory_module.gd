extends Node
## Each player's inventory: a grid of items (Tarkov style) whose rules run in Rust
## (`InventoryGrid`). The server holds every inventory and decides every change; each
## owner gets a copy of theirs after a change, which the Tab screen shows and previews drags
## against. Other modules use the small API below (`count`, `server_give`, `server_take`)
## and the `inventory.changed` topic; item ids for weapon parts are the parts' ids.
## Not saved yet: inventories reset when the server restarts.

const ITEMS := "res://modules/inventory/data/items.json"

var _data: Dictionary = {}
## Item id -> [w, h], for the grids.
var _sizes: Dictionary = {}
## Server: peer id -> InventoryGrid.
var _grids: Dictionary = {}
var _next_uid := 1
## This instance's copy of its own player's inventory (on the server, the same grid).
var _mine: InventoryGrid


func _ready() -> void:
	# Other modules find the API through this group instead of a path into this module.
	add_to_group(&"inventory_api")
	var parsed: Variant = Data.load_json(ITEMS)
	_data = parsed if parsed is Dictionary else {}
	var items: Dictionary = _data.get("items", {})
	for id: String in items:
		_sizes[id] = (items[id] as Dictionary).get("size", [1, 1])
	_mine = _new_grid()
	EventBus.subscribe(&"player.spawned", _on_player_spawned)
	Net.peer_left.connect(_on_peer_left)
	if DisplayServer.get_name() != "headless":
		InputBindings.register(_data.get("bindings", {}), &"inventory")


func _exit_tree() -> void:
	EventBus.unsubscribe(&"player.spawned", _on_player_spawned)
	if Net.peer_left.is_connected(_on_peer_left):
		Net.peer_left.disconnect(_on_peer_left)


## Item definition: `{name, size: [w, h], kind}`, or empty.
func item_info(item: String) -> Dictionary:
	return (_data.get("items", {}) as Dictionary).get(item, {})


func grid_size() -> Vector2i:
	var size: Array = _data.get("grid", [10, 6])
	return Vector2i(int(size[0]), int(size[1]))


func kind_colour(kind: String) -> Color:
	var c: Array = (_data.get("kinds", {}) as Dictionary).get(kind, [0.4, 0.4, 0.4])
	return Color(float(c[0]), float(c[1]), float(c[2]))


## The grid for `peer`: the server's own on the server, this player's copy on a client.
func grid_of(peer: int) -> InventoryGrid:
	if multiplayer.is_server():
		return _grids.get(peer)
	return _mine if peer == multiplayer.get_unique_id() else null


func count(peer: int, item: String) -> int:
	var grid := grid_of(peer)
	return grid.count(item) if grid != null else 0


## Server: puts one `item` into `peer`'s inventory if there is room.
func server_give(peer: int, item: String) -> bool:
	var grid: InventoryGrid = _grids.get(peer)
	if grid == null or item_info(item).is_empty():
		return false
	var result := grid.insert(_next_uid, item)
	if not result["ok"]:
		return false
	_next_uid += 1
	_send(peer)
	return true


## Server: takes one `item` out of `peer`'s inventory if they have one.
func server_take(peer: int, item: String) -> bool:
	var grid: InventoryGrid = _grids.get(peer)
	if grid == null:
		return false
	for placed: Dictionary in grid.items():
		if placed["item"] == item:
			grid.remove(int(placed["uid"]))
			_send(peer)
			return true
	return false


## Client: asks to move an item in this player's inventory.
func request_move(uid: int, x: int, y: int, rotated: bool) -> void:
	if multiplayer.is_server():
		server_move(multiplayer.get_unique_id(), uid, x, y, rotated)
	else:
		_request_move.rpc_id(1, uid, x, y, rotated)


@rpc("any_peer", "call_remote", "reliable")
func _request_move(uid: int, x: int, y: int, rotated: bool) -> void:
	if multiplayer.is_server():
		server_move(multiplayer.get_remote_sender_id(), uid, x, y, rotated)


## Server: moves an item if the grid rules allow it. The owner gets the result either way,
## so a refused drag snaps back.
func server_move(peer: int, uid: int, x: int, y: int, rotated: bool) -> bool:
	var grid: InventoryGrid = _grids.get(peer)
	if grid == null:
		return false
	var why := grid.move_item(uid, x, y, rotated)
	if not why.is_empty():
		Log.info(&"inventory", "peer %d: move refused: %s" % [peer, why])
	_send(peer)
	return why.is_empty()


func _on_player_spawned(p: Dictionary) -> void:
	var player: Node = p["player"]
	var peer := int(player.get_meta(&"peer_id", 1))
	if multiplayer.is_server() and not _grids.has(peer):
		var grid := _new_grid() if peer != multiplayer.get_unique_id() else _mine
		_grids[peer] = grid
		for item: String in _data.get("starting_kit", []):
			var result := grid.insert(_next_uid, item)
			if result["ok"]:
				_next_uid += 1
		_send(peer)
	if DisplayServer.get_name() != "headless" and p.get("local", false):
		var screen := InventoryScreen.new()
		screen.name = "InventoryScreen"
		screen.inventory = self
		screen.peer = peer
		add_child(screen)


func _on_peer_left(peer: int) -> void:
	_grids.erase(peer)


func _new_grid() -> InventoryGrid:
	var size: Array = _data.get("grid", [10, 6])
	var grid := InventoryGrid.new()
	grid.setup(int(size[0]), int(size[1]), _sizes)
	return grid


## Server: sends `peer` their inventory. On the server's own player it is already current.
func _send(peer: int) -> void:
	if peer == multiplayer.get_unique_id():
		EventBus.publish(&"inventory.changed", {"peer": peer})
		return
	var grid: InventoryGrid = _grids.get(peer)
	if grid != null and multiplayer.get_peers().has(peer):
		_receive.rpc_id(peer, grid.items())
	EventBus.publish(&"inventory.changed", {"peer": peer})


@rpc("authority", "call_remote", "reliable")
func _receive(items: Array) -> void:
	_mine = _new_grid()
	for placed: Dictionary in items:
		_mine.place(int(placed["uid"]), str(placed["item"]), int(placed["x"]), int(placed["y"]), bool(placed["rotated"]))
	EventBus.publish(&"inventory.changed", {"peer": multiplayer.get_unique_id()})
