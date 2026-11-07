extends Node
## Each player's inventory: a grid of items (Tarkov style) whose rules run in Rust
## (`InventoryGrid`). The server holds every inventory and decides every change; each
## owner gets a copy of theirs after a change, which the Tab screen shows and previews drags
## against. Other modules use the small API below (`count`, `server_give`, `server_take`)
## and the `inventory.changed` topic; item ids for weapon parts are the parts' ids.
## Not saved yet: inventories reset when the server restarts.

const ITEMS := "res://modules/inventory/data/items.json"
## Reach for picking things up, metres from the eye, and how squarely you must face it.
const PICKUP_RANGE := 2.6
const PICKUP_FACING := 0.5
const DROP_DISTANCE := 1.0
const PILE_RADIUS := 0.45

var _data: Dictionary = {}
## Item id -> [w, h], for the grids.
var _sizes: Dictionary = {}
## Server: peer id -> InventoryGrid.
var _grids: Dictionary = {}
var _next_uid := 1
var _loot_spawner := MultiplayerSpawner.new()
var _loot_count := 0
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
	# Loot on the ground is created by the server and replicated, like the car.
	_loot_spawner.name = "LootSpawner"
	_loot_spawner.spawn_path = NodePath("..")
	_loot_spawner.spawn_function = _make_loot
	add_child(_loot_spawner)
	EventBus.subscribe(&"player.spawned", _on_player_spawned)
	EventBus.subscribe(&"player.interact", _on_player_interact)
	EventBus.subscribe(&"world.ready", _on_world_ready)
	Net.peer_left.connect(_on_peer_left)
	if DisplayServer.get_name() != "headless":
		InputBindings.register(_data.get("bindings", {}), &"inventory")


func _exit_tree() -> void:
	EventBus.unsubscribe(&"player.spawned", _on_player_spawned)
	EventBus.unsubscribe(&"player.interact", _on_player_interact)
	EventBus.unsubscribe(&"world.ready", _on_world_ready)
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
		var prompt := LootPrompt.new()
		prompt.name = "LootPrompt"
		prompt.inventory = self
		prompt.player = player as Node3D
		add_child(prompt)
		var screen := InventoryScreen.new()
		screen.name = "InventoryScreen"
		screen.inventory = self
		screen.peer = peer
		add_child(screen)


## Server: puts `item` on the ground at `at`; everyone sees it.
func server_spawn_loot(item: String, at: Vector3) -> LootItem:
	if item_info(item).is_empty():
		return null
	_loot_count += 1
	return _loot_spawner.spawn({"index": _loot_count, "item": item, "position": at})


## Runs on the server and, through the spawner, on every client.
func _make_loot(data: Variant) -> Node:
	var info: Dictionary = data
	var item := str(info["item"])
	var def := item_info(item)
	var loot := LootItem.new()
	loot.name = "Loot%d" % int(info["index"])
	loot.item = item
	loot.short_name = str(def.get("short", def.get("name", item)))
	loot.colour = kind_colour(str(def.get("kind", "")))
	var size: Array = def.get("size", [1, 1])
	loot.cells = Vector2i(int(size[0]), int(size[1]))
	loot.position = info["position"]
	loot.rotation.y = float(int(info["index"]) * 37 % 360) * PI / 180.0
	# Other modules (weapons) may dress it with the real model.
	EventBus.publish(&"inventory.loot_spawned", {"loot": loot, "item": item})
	return loot


## The loot `player` would pick up now: the nearest within reach, roughly in front.
func loot_in_reach(player: Node3D) -> LootItem:
	var head := player.get_node_or_null("Head/Camera") as Node3D
	var eye := head.global_position if head != null else player.global_position + Vector3.UP * 1.6
	var forward := -head.global_transform.basis.z if head != null else -player.global_transform.basis.z
	var best: LootItem = null
	var best_d := PICKUP_RANGE
	for node: Node in get_tree().get_nodes_in_group(&"loot"):
		var loot := node as LootItem
		if loot == null or loot.is_queued_for_deletion():
			continue
		var to := loot.global_position - eye
		var d := to.length()
		if d < best_d and forward.dot(to.normalized()) > PICKUP_FACING:
			best = loot
			best_d = d
	return best


## Server: E near loot picks it up if it fits. Claims the press so the car does not also
## take it.
func _on_player_interact(payload: Dictionary) -> void:
	if not multiplayer.is_server() or payload.get("handled", false):
		return
	var player: Node3D = payload["player"]
	var loot := loot_in_reach(player)
	if loot == null:
		return
	payload["handled"] = true
	var peer := int(player.get_meta(&"peer_id", 1))
	if server_give(peer, loot.item):
		loot.queue_free()
	else:
		Log.info(&"inventory", "peer %d: no room for %s" % [peer, loot.item])


## Client: drops an item from this player's inventory in front of them.
func request_drop(uid: int) -> void:
	if multiplayer.is_server():
		server_drop(multiplayer.get_unique_id(), uid)
	else:
		_request_drop.rpc_id(1, uid)


@rpc("any_peer", "call_remote", "reliable")
func _request_drop(uid: int) -> void:
	if multiplayer.is_server():
		server_drop(multiplayer.get_remote_sender_id(), uid)


## Server: takes the item out of `peer`'s inventory and lays it on the ground in front of
## their player.
func server_drop(peer: int, uid: int) -> bool:
	var grid: InventoryGrid = _grids.get(peer)
	var player := _player_of(peer)
	if grid == null or player == null:
		return false
	var item := ""
	for placed: Dictionary in grid.items():
		if int(placed["uid"]) == uid:
			item = str(placed["item"])
	if item.is_empty() or not grid.remove(uid):
		return false
	var front := player.global_position - player.global_transform.basis.z * DROP_DISTANCE
	server_spawn_loot(item, _on_ground(front))
	_send(peer)
	return true


## Server: the loot piles near the spawn, once the ground there exists.
func _on_world_ready(payload: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var spawn: Vector3 = payload.get("spawn", Vector3.ZERO)
	for pile: Dictionary in _data.get("loot", []):
		var offset: Array = pile.get("at", [0, 0])
		var centre := spawn + Vector3(float(offset[0]), 0.0, float(offset[1]))
		var items: Array = pile.get("items", [])
		for i in items.size():
			var a := TAU * i / maxf(1.0, items.size())
			server_spawn_loot(str(items[i]), _on_ground(centre + Vector3(cos(a), 0.0, sin(a)) * PILE_RADIUS))


func _player_of(peer: int) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		if int(node.get_meta(&"peer_id", 1)) == peer:
			return node as Node3D
	return null


## The ground under `at` (a physics ray down), or `at` itself if nothing is there.
func _on_ground(at: Vector3) -> Vector3:
	var world := get_viewport().find_world_3d()
	if world == null:
		return at
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 20.0, at + Vector3.DOWN * 40.0)
	query.collide_with_areas = false
	var exclude: Array[RID] = []
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		if node is CollisionObject3D:
			exclude.append((node as CollisionObject3D).get_rid())
	query.exclude = exclude
	var hit := world.direct_space_state.intersect_ray(query)
	return hit["position"] if not hit.is_empty() else at


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
