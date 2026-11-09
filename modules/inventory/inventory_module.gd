extends Node
## Each player's inventory: a grid of items whose rules run in Rust
## (`InventoryGrid`). The server holds every inventory and decides every change; each
## owner gets a copy of theirs after a change, which the Tab screen shows and previews drags
## against. Other modules use the small API below (`count`, `server_give`, `server_take`)
## and the `inventory.changed` topic; item ids for weapon parts are the parts' ids.
## Saving is someone else's job: `server_items_of` / `server_restore_items` and
## `server_world_state` / `server_restore_world` hand the state out and take it back.

## Ground probes start this far over the untouched ground, or over the point itself.
## Saved loot this far under the ground is inside it (the world changed since the save).
const BURIED_DEPTH := 1.0
const PROBE_ABOVE_GROUND := 3.0
const PROBE_ABOVE_SELF := 1.5
const ITEMS := "res://modules/inventory/data/items.json"
## Reach for picking things up, metres from the eye, and how squarely you must face it.
const PICKUP_RANGE := 2.6
const PICKUP_FACING := 0.8
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
var _crate_spawner := MultiplayerSpawner.new()
## Server: crate -> item ids inside; crate -> seconds until it refills.
var _crate_items: Dictionary = {}
var _crate_refill: Dictionary = {}
## Server: crates in spawn order; a crate's index here is how a save names it.
var _crates: Array[LootCrate] = []
## Server: player -> {per_second, left} while a medkit works.
var _healing: Dictionary = {}
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
	_crate_spawner.name = "CrateSpawner"
	_crate_spawner.spawn_path = NodePath("..")
	_crate_spawner.spawn_function = _make_crate
	add_child(_crate_spawner)
	EventBus.subscribe(&"player.spawned", _on_player_spawned)
	EventBus.subscribe(&"player.interact", _on_player_interact)
	EventBus.subscribe(&"world.ready", _on_world_ready)
	EventBus.subscribe(&"player.died", _on_player_died)
	EventBus.subscribe(&"enemy.died", _on_enemy_died)
	EventBus.subscribe(&"inventory.crate_changed", _on_crate_changed)
	EventBus.subscribe(&"admin.spawn", _on_admin_spawn)
	Net.peer_left.connect(_on_peer_left)
	Net.peer_joined.connect(_on_peer_joined)
	if DisplayServer.get_name() != "headless":
		InputBindings.register(_data.get("bindings", {}), &"inventory")


func _exit_tree() -> void:
	EventBus.unsubscribe(&"player.spawned", _on_player_spawned)
	EventBus.unsubscribe(&"player.interact", _on_player_interact)
	EventBus.unsubscribe(&"world.ready", _on_world_ready)
	EventBus.unsubscribe(&"player.died", _on_player_died)
	EventBus.unsubscribe(&"enemy.died", _on_enemy_died)
	EventBus.unsubscribe(&"inventory.crate_changed", _on_crate_changed)
	EventBus.unsubscribe(&"admin.spawn", _on_admin_spawn)
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
		# Players start with a kit; enemies carry a few random things worth killing them for.
		var npc: bool = p.get("npc", false)
		for item: String in (_roll_loot() if npc else Array(_data.get("starting_kit", []))):
			var result := grid.insert(_next_uid, item)
			if result["ok"]:
				_next_uid += 1
		if not npc:
			_send(peer)
	if DisplayServer.get_name() != "headless" and p.get("local", false):
		var prompt := LootPrompt.new()
		prompt.name = "LootPrompt"
		prompt.inventory = self
		prompt.player = player as Node3D
		prompt.peer = peer
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
	var best_facing := PICKUP_FACING
	for node: Node in get_tree().get_nodes_in_group(&"loot"):
		var loot := node as LootItem
		if loot == null or loot.is_queued_for_deletion():
			continue
		var to := loot.global_position - eye
		var facing := forward.dot(to.normalized())
		# What the crosshair is closest to wins, not what is nearest.
		if to.length() < PICKUP_RANGE and facing > best_facing:
			best = loot
			best_facing = facing
	if best == null:
		return null
	# A crate the crosshair is more squarely on takes the press instead.
	var crate := _crate_facing(eye, forward)
	if crate.size() > 0 and float(crate[1]) > best_facing:
		return null
	return best


## The crate `player` would search now, or null.
func crate_in_reach(player: Node3D) -> LootCrate:
	var head := player.get_node_or_null("Head/Camera") as Node3D
	var eye := head.global_position if head != null else player.global_position + Vector3.UP * 1.6
	var forward := -head.global_transform.basis.z if head != null else -player.global_transform.basis.z
	var found := _crate_facing(eye, forward)
	return found[0] if found.size() > 0 else null


## [crate, facing] for the crate the crosshair is most squarely on within reach, or [].
func _crate_facing(eye: Vector3, forward: Vector3) -> Array:
	var best: LootCrate = null
	# A crate is big; a looser aim still counts.
	var best_facing := PICKUP_FACING - 0.1
	for node: Node in get_tree().get_nodes_in_group(&"crates"):
		var crate := node as LootCrate
		if crate == null:
			continue
		var to := crate.global_position + Vector3.UP * 0.3 - eye
		var facing := forward.dot(to.normalized())
		if to.length() < PICKUP_RANGE + 0.4 and facing > best_facing:
			best = crate
			best_facing = facing
	return [best, best_facing] if best != null else []


## Server: E near loot picks it up if it fits, or searches a crate. Claims the press so
## the car does not also take it.
func _on_player_interact(payload: Dictionary) -> void:
	if not multiplayer.is_server() or payload.get("handled", false):
		return
	var player: Node3D = payload["player"]
	var loot := loot_in_reach(player)
	if loot == null:
		var crate := crate_in_reach(player)
		if crate != null:
			payload["handled"] = true
			server_search(int(player.get_meta(&"peer_id", 1)), crate)
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


## Server: the loot piles near the spawn, once the ground there exists, and the crates
## spread over the map (the same places every session, from the seed).
func _on_world_ready(payload: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var spawn: Vector3 = payload.get("spawn", Vector3.ZERO)
	# Crates spread around the road outside the start tunnel, on its open side.
	var front: Vector3 = payload.get("front", spawn)
	var forward: Vector3 = payload.get("forward", Vector3.ZERO)
	var crates: Dictionary = _data.get("crates", {})
	var place := RandomNumberGenerator.new()
	place.seed = int(crates.get("seed", 1))
	var ring: Array = crates.get("distance", [10.0, 100.0])
	for i in int(crates.get("count", 0)):
		var a := place.randf() * TAU
		if forward != Vector3.ZERO:
			a = atan2(forward.z, forward.x) + (a / TAU - 0.5) * PI
		var d := place.randf_range(float(ring[0]), float(ring[1]))
		server_spawn_crate(_on_ground(front + Vector3(cos(a), 0.0, sin(a)) * d))
	for pile: Dictionary in _data.get("loot", []):
		var offset: Array = pile.get("at", [0, 0])
		var centre := spawn + Vector3(float(offset[0]), 0.0, float(offset[1]))
		var items: Array = pile.get("items", [])
		for i in items.size():
			var a := TAU * i / maxf(1.0, items.size())
			server_spawn_loot(str(items[i]), _on_ground(centre + Vector3(cos(a), 0.0, sin(a)) * PILE_RADIUS))


## Server: dying spills the whole backpack on the ground where the player fell, for them
## (or a friend) to go back for.
func _on_enemy_died(p: Dictionary) -> void:
	_on_player_died({"player": p.get("enemy"), "position": p.get("position")})
	# The body goes away soon; so does its empty backpack.
	var enemy := p.get("enemy") as Node
	if enemy != null:
		_grids.erase(int(enemy.get_meta(&"peer_id", 0)))


## Item ids for an enemy's pockets: a few rolls on the weighted loot table.
func _roll_loot() -> Array:
	return _roll(_data.get("npc_loot", {}))


func _on_player_died(p: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var player := p.get("player") as Node3D
	if player == null:
		return
	var peer := int(player.get_meta(&"peer_id", 1))
	var grid: InventoryGrid = _grids.get(peer)
	if grid == null:
		return
	var at: Vector3 = p.get("position", player.global_position)
	var items := grid.items()
	for i in items.size():
		grid.remove(int(items[i]["uid"]))
		var a := TAU * i / maxf(1.0, items.size())
		var r := PILE_RADIUS + 0.12 * (i % 3)
		server_spawn_loot(str(items[i]["item"]), _on_ground(at + Vector3(cos(a) * r, 0.0, sin(a) * r)))
	_send(peer)


## Server: moves a crate's contents into `peer`'s backpack, as much as fits. An emptied
## crate refills later.
func server_search(peer: int, crate: LootCrate) -> int:
	var items: Array = _crate_items.get(crate, [])
	var taken := 0
	for item: String in items.duplicate():
		if server_give(peer, item):
			items.erase(item)
			taken += 1
	_crate_items[crate] = items
	if items.is_empty() and not crate.get_meta(&"empty", false):
		_crate_refill[crate] = float((_data.get("crates", {}) as Dictionary).get("refill_seconds", 120.0))
		Net.server_broadcast(&"inventory.crate_changed", {"crate": crate, "empty": true})
	return taken


func crate_contents(crate: LootCrate) -> Array:
	return _crate_items.get(crate, [])


## Server: puts a crate on the ground with a roll of contents.
func server_spawn_crate(at: Vector3) -> LootCrate:
	_loot_count += 1
	var crate: LootCrate = _crate_spawner.spawn({"index": _loot_count, "position": at})
	_crate_items[crate] = _roll(_data.get("crates", {}))
	_crates.append(crate)
	return crate


func _make_crate(data: Variant) -> Node:
	var info: Dictionary = data
	var crate := LootCrate.new()
	crate.name = "Crate%d" % int(info["index"])
	crate.position = info["position"]
	crate.rotation.y = float(int(info["index"]) * 53 % 360) * PI / 180.0
	return crate


func _on_crate_changed(p: Dictionary) -> void:
	var crate := p.get("crate") as LootCrate
	if crate != null:
		crate.set_empty(bool(p.get("empty", false)))


## Server: H (or a right click on it in the backpack) uses an item: a medkit heals over a
## few seconds. Returns false if there is none or nothing to heal.
func server_use(peer: int, item: String) -> bool:
	var use: Dictionary = item_info(item).get("use", {})
	var player := _player_of(peer)
	if use.is_empty() or player == null or player.get_meta(&"dead", false):
		return false
	var health := player.get_node_or_null("Health") as HealthComponent
	if health == null or health.health >= health.max_health or _healing.has(player):
		return false
	if not server_take(peer, item):
		return false
	var seconds := maxf(float(use.get("seconds", 1.0)), 0.01)
	_healing[player] = {"per_second": float(use.get("heal", 0.0)) / seconds, "left": seconds}
	return true


func request_use(item: String) -> void:
	if multiplayer.is_server():
		server_use(multiplayer.get_unique_id(), item)
	else:
		_request_use.rpc_id(1, item)


@rpc("any_peer", "call_remote", "reliable")
func _request_use(item: String) -> void:
	if multiplayer.is_server():
		server_use(multiplayer.get_remote_sender_id(), item)


func _physics_process(delta: float) -> void:
	var prof := Prof.start()
	_physics_tick(delta)
	Prof.stop(&"inventory/module:physics", prof)


func _physics_tick(delta: float) -> void:
	if not multiplayer.is_server():
		return
	for player: Node in _healing.keys():
		var h: Dictionary = _healing[player]
		var health := player.get_node_or_null("Health") as HealthComponent if is_instance_valid(player) else null
		if health == null or player.get_meta(&"dead", false):
			_healing.erase(player)
			continue
		var step := minf(delta, float(h["left"]))
		health.server_heal(float(h["per_second"]) * step)
		h["left"] = float(h["left"]) - step
		if float(h["left"]) <= 0.0:
			_healing.erase(player)
	for crate: Node in _crate_refill.keys():
		if not is_instance_valid(crate):
			_crate_refill.erase(crate)
			continue
		_crate_refill[crate] = float(_crate_refill[crate]) - delta
		if float(_crate_refill[crate]) <= 0.0:
			_crate_refill.erase(crate)
			_crate_items[crate] = _roll(_data.get("crates", {}))
			Net.server_broadcast(&"inventory.crate_changed", {"crate": crate, "empty": false})


## Item ids from a loot table `{rolls: [min, max], items: {id: weight}}`.
func _roll(table_def: Dictionary) -> Array:
	var table: Dictionary = table_def.get("items", {})
	var rolls: Array = table_def.get("rolls", [1, 2])
	var total := 0.0
	for id: String in table:
		total += float(table[id])
	var out := []
	if total <= 0.0:
		return out
	for i in randi_range(int(rolls[0]), int(rolls[1])):
		var pick := randf() * total
		for id: String in table:
			pick -= float(table[id])
			if pick <= 0.0:
				out.append(id)
				break
	return out


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
	# From just over the ground (or over `at` when that is higher, e.g. on a roof), not from
	# high above: under a roof, like in the start tunnel, that would land on the roof.
	var from_y := at.y + 20.0
	var ground_node := get_tree().get_first_node_in_group(&"ground")
	if ground_node != null and ground_node.has_method(&"ground_height"):
		from_y = maxf(at.y + PROBE_ABOVE_SELF, float(ground_node.call(&"ground_height", at.x, at.z)) + PROBE_ABOVE_GROUND)
	var query := PhysicsRayQueryParameters3D.create(Vector3(at.x, from_y, at.z), at + Vector3.DOWN * 40.0, PhysicsLayers.SOLID)
	query.collide_with_areas = false
	var exclude: Array[RID] = []
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		if node is CollisionObject3D:
			exclude.append((node as CollisionObject3D).get_rid())
	query.exclude = exclude
	var hit := world.direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		return hit["position"]
	# Far from players the server has no terrain loaded; the height map knows anyway.
	var ground := get_tree().get_first_node_in_group(&"ground")
	if ground != null and ground.has_method(&"ground_height"):
		return Vector3(at.x, float(ground.call(&"ground_height", at.x, at.z)), at.z)
	return at


func _on_peer_left(peer: int) -> void:
	_grids.erase(peer)


## Server: a friend who joins late sees which crates are already emptied.
func _on_peer_joined(peer: int) -> void:
	if not multiplayer.is_server():
		return
	var emptied: Array[String] = []
	for crate in _crates:
		if is_instance_valid(crate) and crate.get_meta(&"empty", false):
			emptied.append(String(crate.name))
	if not emptied.is_empty():
		_receive_emptied.rpc_id(peer, emptied)


@rpc("authority", "call_remote", "reliable")
func _receive_emptied(names: Array) -> void:
	for crate_name: Variant in names:
		var crate := get_node_or_null(NodePath(str(crate_name))) as LootCrate
		if crate != null:
			crate.set_empty(true)


## Server: `peer`'s backpack as `[{item, x, y, rotated}]`, for saving.
func server_items_of(peer: int) -> Array:
	var grid: InventoryGrid = _grids.get(peer)
	var out := []
	if grid == null:
		return out
	for placed: Dictionary in grid.items():
		out.append({"item": placed["item"], "x": placed["x"], "y": placed["y"], "rotated": placed["rotated"]})
	return out


## Server: replaces `peer`'s backpack with saved items, each where it was. Anything that no
## longer fits there (the grid or an item's size changed) goes in the first free spot, and
## what has no room at all lands at the player's feet rather than vanishing.
func server_restore_items(peer: int, items: Array) -> void:
	var grid := _new_grid() if peer != multiplayer.get_unique_id() else _mine
	if grid == _mine:
		for placed: Dictionary in grid.items():
			grid.remove(int(placed["uid"]))
	_grids[peer] = grid
	var spilled: Array[String] = []
	for saved: Dictionary in items:
		var item := str(saved.get("item", ""))
		if item_info(item).is_empty():
			Log.warn(&"inventory", "peer %d: dropped unknown saved item '%s'" % [peer, item])
			continue
		var placed := grid.place(_next_uid, item, int(saved.get("x", 0)), int(saved.get("y", 0)), bool(saved.get("rotated", false)))
		if not placed.is_empty() and not grid.insert(_next_uid, item)["ok"]:
			spilled.append(item)
			continue
		_next_uid += 1
	var player := _player_of(peer)
	for item in spilled:
		if player != null:
			server_spawn_loot(item, _on_ground(player.global_position))
	_send(peer)


## Server: loose loot and crate state, for saving: `{loot: [{item, position}], crates:
## [{index, items, refill_seconds}]}`, refill_seconds -1 for a crate not waiting to refill.
func server_world_state() -> Dictionary:
	var loot := []
	for node: Node in get_tree().get_nodes_in_group(&"loot"):
		var item := node as LootItem
		if item != null and not item.is_queued_for_deletion():
			loot.append({"item": item.item, "position": item.global_position})
	var crates := []
	for i in _crates.size():
		var crate := _crates[i]
		if not is_instance_valid(crate):
			continue
		crates.append({"index": i, "items": (_crate_items.get(crate, []) as Array).duplicate(), "refill_seconds": float(_crate_refill.get(crate, -1.0))})
	return {"loot": loot, "crates": crates}


## Server: puts the world back as saved: the loot on the ground replaces whatever this
## session laid out, and crates take back their contents and refill timers. Crates match by
## spawn order; extra saved ones (fewer crates now) are ignored.
func server_restore_world(state: Dictionary) -> void:
	for node: Node in get_tree().get_nodes_in_group(&"loot"):
		node.queue_free()
	var ground := get_tree().get_first_node_in_group(&"ground")
	for saved: Dictionary in state.get("loot", []):
		var at: Vector3 = saved.get("position", Vector3.ZERO)
		# The world may have changed since the save; loot now inside the ground is gone.
		if ground != null and ground.has_method(&"ground_height") and at.y < float(ground.call(&"ground_height", at.x, at.z)) - BURIED_DEPTH:
			continue
		server_spawn_loot(str(saved.get("item", "")), at)
	for saved: Dictionary in state.get("crates", []):
		var i := int(saved.get("index", -1))
		if i < 0 or i >= _crates.size() or not is_instance_valid(_crates[i]):
			continue
		var crate := _crates[i]
		var items: Array = []
		for item: Variant in saved.get("items", []):
			if not item_info(str(item)).is_empty():
				items.append(str(item))
		_crate_items[crate] = items
		var refill := float(saved.get("refill_seconds", -1.0))
		if items.is_empty() and refill < 0.0:
			refill = float((_data.get("crates", {}) as Dictionary).get("refill_seconds", 120.0))
		if refill >= 0.0:
			_crate_refill[crate] = refill
		else:
			_crate_refill.erase(crate)
		var empty := items.is_empty()
		if empty != bool(crate.get_meta(&"empty", false)):
			Net.server_broadcast(&"inventory.crate_changed", {"crate": crate, "empty": empty})


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


## Server: an admin asked for a crate, or a roll of loot scattered on the ground.
func _on_admin_spawn(p: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var at: Vector3 = p["position"]
	match p.get("kind"):
		"crate":
			server_spawn_crate(at)
		"loot":
			var i := 0
			for item: String in _roll_loot():
				server_spawn_loot(item, at + Vector3(cos(i * 1.3), 0.6, sin(i * 1.3)) * 0.8)
				i += 1
