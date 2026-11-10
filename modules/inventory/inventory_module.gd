extends Node
## Each player's gear: equipment slots (rig, backpack) and grids (pockets, plus the grids a
## worn rig and backpack open), whose rules run in Rust (`InventoryGear`). The server holds every inventory and decides every change; each
## owner gets a copy of theirs after a change, which the Tab screen shows and previews drags
## against. Crates and the bodies of the dead are containers with a grid of their own:
## searching one opens the loot screen (yours and theirs side by side), and every move
## between the two is a request the server checks. Other modules use the small API below (`count`, `server_give`, `server_take`)
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
## How far from a body or crate you may be while its loot screen stays open.
const LOOT_REACH := PICKUP_RANGE + 1.0
## Where the crosshair aims on a crate or a body, above its origin.
const CRATE_AIM := 0.3
const BODY_AIM := 0.15
const PILE_RADIUS := 0.45

var _data: Dictionary = {}
## Item id -> {size, kind, grid}, for the gear rules.
var _defs: Dictionary = {}
## Server: peer id -> InventoryGear.
var _grids: Dictionary = {}
var _next_uid := 1
var _loot_spawner := MultiplayerSpawner.new()
var _loot_count := 0
var _crate_spawner := MultiplayerSpawner.new()
var _body_spawner := MultiplayerSpawner.new()
## Server: container id -> InventoryGear for every crate and body, and id -> its node.
var _containers: Dictionary = {}
var _container_nodes: Dictionary = {}
var _next_container := 1
## Server: crate -> seconds until it refills; body container id -> seconds it has left.
var _crate_refill: Dictionary = {}
var _body_left: Dictionary = {}
## Server: peer -> the container id whose loot screen they have open.
var _viewers: Dictionary = {}
## Server: crates in spawn order; a crate's index here is how a save names it.
var _crates: Array[LootCrate] = []
## Server: player -> {per_second, left} while a medkit works.
var _healing: Dictionary = {}
## This instance's copy of its own player's inventory (on the server, the same grid).
var _mine: InventoryGear
## This instance's copy of the container its player has open (on the server, the same
## grid), or null, and its title for the screen.
var _theirs: InventoryGear
var _theirs_title := ""


func _ready() -> void:
	# Other modules find the API through this group instead of a path into this module.
	add_to_group(&"inventory_api")
	var parsed: Variant = Data.load_json(ITEMS)
	_data = parsed if parsed is Dictionary else {}
	var items: Dictionary = _data.get("items", {})
	for id: String in items:
		var def: Dictionary = items[id]
		_defs[id] = {"size": def.get("size", [1, 1]), "kind": def.get("kind", ""), "grid": def.get("grid", null)}
		if def.get("grid", null) == null:
			(_defs[id] as Dictionary).erase("grid")
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
	_body_spawner.name = "BodySpawner"
	_body_spawner.spawn_path = NodePath("..")
	_body_spawner.spawn_function = _make_body
	add_child(_body_spawner)
	EventBus.subscribe(&"player.spawned", _on_player_spawned)
	EventBus.subscribe(&"player.interact", _on_player_interact)
	EventBus.subscribe(&"world.ready", _on_world_ready)
	EventBus.subscribe(&"player.died", _on_player_died)
	EventBus.subscribe(&"enemy.died", _on_enemy_died)
	EventBus.subscribe(&"inventory.container_state", _on_container_state)
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
	EventBus.unsubscribe(&"inventory.container_state", _on_container_state)
	EventBus.unsubscribe(&"admin.spawn", _on_admin_spawn)
	if Net.peer_left.is_connected(_on_peer_left):
		Net.peer_left.disconnect(_on_peer_left)


## Item definition: `{name, size: [w, h], kind}`, or empty.
func item_info(item: String) -> Dictionary:
	return (_data.get("items", {}) as Dictionary).get(item, {})


## Read-only gun slots for the gear screen, `{slot: label}` (guns are not items yet).
func weapon_labels() -> Dictionary:
	return (_data.get("gear", {}) as Dictionary).get("weapons", {})


func kind_colour(kind: String) -> Color:
	var c: Array = (_data.get("kinds", {}) as Dictionary).get(kind, [0.4, 0.4, 0.4])
	return Color(float(c[0]), float(c[1]), float(c[2]))


## The gear of `peer`: the server's own on the server, this player's copy on a client.
func grid_of(peer: int) -> InventoryGear:
	if multiplayer.is_server():
		return _grids.get(peer)
	return _mine if peer == multiplayer.get_unique_id() else null


func count(peer: int, item: String) -> int:
	var gear := grid_of(peer)
	return gear.count(item) if gear != null else 0


## Server: puts one `item` into `peer`'s gear if there is room (an empty slot of its kind
## first, then the rig, pockets and backpack).
func server_give(peer: int, item: String) -> bool:
	var gear: InventoryGear = _grids.get(peer)
	if gear == null or item_info(item).is_empty():
		return false
	if not gear.insert(_next_uid, item)["ok"]:
		return false
	_next_uid += 1
	_send(peer)
	return true


## Server: takes one `item` out of `peer`'s gear if they have one.
func server_take(peer: int, item: String) -> bool:
	var gear: InventoryGear = _grids.get(peer)
	if gear == null:
		return false
	for placed: Dictionary in gear.all_items():
		if placed["item"] == item and gear.remove(int(placed["uid"])).is_empty():
			_send(peer)
			return true
	return false


## Client: asks to move an item within this player's gear to `place` (`{slot: name}` or
## `{grid: name, x, y, rotated}`).
func request_move(uid: int, place: Dictionary) -> void:
	if multiplayer.is_server():
		server_move(multiplayer.get_unique_id(), uid, place)
	else:
		_request_move.rpc_id(1, uid, place)


@rpc("any_peer", "call_remote", "reliable")
func _request_move(uid: int, place: Dictionary) -> void:
	if multiplayer.is_server():
		server_move(multiplayer.get_remote_sender_id(), uid, place)


## Server: moves an item if the gear rules allow it. The owner gets the result either way,
## so a refused drag snaps back.
func server_move(peer: int, uid: int, place: Dictionary) -> bool:
	var gear: InventoryGear = _grids.get(peer)
	if gear == null:
		return false
	var why := gear.move_item(uid, place)
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
		# Players start with a rig, a pack and a kit; enemies wear their gear and carry a few
		# random things worth killing them for.
		var npc: bool = p.get("npc", false)
		_wear(grid, _data.get("npc_gear" if npc else "starting_gear", {}))
		_fill(grid, _roll_loot() if npc else Array(_data.get("starting_kit", [])))
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
		var loot_screen := LootScreen.new()
		loot_screen.name = "LootScreen"
		loot_screen.inventory = self
		loot_screen.peer = peer
		add_child(loot_screen)


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
	# A crate or body the crosshair is more squarely on takes the press instead.
	var crate := _container_facing(eye, forward)
	if crate.size() > 0 and float(crate[1]) > best_facing:
		return null
	return best


## The crate or body `player` would search now, or null.
func container_in_reach(player: Node3D) -> Node3D:
	var head := player.get_node_or_null("Head/Camera") as Node3D
	var eye := head.global_position if head != null else player.global_position + Vector3.UP * 1.6
	var forward := -head.global_transform.basis.z if head != null else -player.global_transform.basis.z
	var found := _container_facing(eye, forward)
	return found[0] if found.size() > 0 else null


## [node, facing] for the crate or body the crosshair is most squarely on within reach, or [].
func _container_facing(eye: Vector3, forward: Vector3) -> Array:
	var best: Node3D = null
	# Crates and bodies are big; a looser aim still counts.
	var best_facing := PICKUP_FACING - 0.1
	for group: StringName in [&"crates", &"loot_bodies"]:
		var aim := CRATE_AIM if group == &"crates" else BODY_AIM
		for node: Node in get_tree().get_nodes_in_group(group):
			var target := node as Node3D
			if target == null or target.is_queued_for_deletion():
				continue
			var to := target.global_position + Vector3.UP * aim - eye
			var facing := forward.dot(to.normalized())
			if to.length() < PICKUP_RANGE + 0.4 and facing > best_facing:
				best = target
				best_facing = facing
	return [best, best_facing] if best != null else []


## Server: E near loot picks it up if it fits, or opens the loot screen on a crate or body.
## Claims the press so the car does not also take it.
func _on_player_interact(payload: Dictionary) -> void:
	if not multiplayer.is_server() or payload.get("handled", false):
		return
	var player: Node3D = payload["player"]
	var peer := int(player.get_meta(&"peer_id", 1))
	var loot := loot_in_reach(player)
	if loot == null:
		var container := container_in_reach(player)
		if container != null:
			payload["handled"] = true
			server_open(peer, container)
		return
	payload["handled"] = true
	if server_give(peer, loot.item):
		loot.queue_free()
	else:
		Log.info(&"inventory", "peer %d: no room for %s" % [peer, loot.item])


## Client: drops an item from this player's inventory (or from the open body or crate) in
## front of them.
func request_drop(uid: int, from_theirs: bool = false) -> void:
	if multiplayer.is_server():
		server_drop(multiplayer.get_unique_id(), uid, from_theirs)
	else:
		_request_drop.rpc_id(1, uid, from_theirs)


@rpc("any_peer", "call_remote", "reliable")
func _request_drop(uid: int, from_theirs: bool) -> void:
	if multiplayer.is_server():
		server_drop(multiplayer.get_remote_sender_id(), uid, from_theirs)


## Server: takes the item out of `peer`'s inventory (or what they have open) and lays it on
## the ground in front of their player.
func server_drop(peer: int, uid: int, from_theirs: bool = false) -> bool:
	var grid: InventoryGear = _session(peer) if from_theirs else _grids.get(peer)
	var player := _player_of(peer)
	if grid == null or player == null:
		if from_theirs:
			_after_move(peer, uid, "nothing open in reach", true)
		return false
	var item := ""
	for placed: Dictionary in grid.all_items():
		if int(placed["uid"]) == uid:
			item = str(placed["item"])
	var why := "no item %d there" % uid if item.is_empty() else grid.remove(uid)
	if not why.is_empty():
		if from_theirs:
			_after_move(peer, uid, why, true)
		else:
			Log.info(&"inventory", "peer %d: drop refused: %s" % [peer, why])
			_send(peer)
		return false
	var front := player.global_position - player.global_transform.basis.z * DROP_DISTANCE
	server_spawn_loot(item, _on_ground(front))
	if from_theirs:
		_after_move(peer, uid, "", true)
	else:
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


## Server: a dead soldier's gear stays on its body; so does a player's.
func _on_enemy_died(p: Dictionary) -> void:
	_on_player_died({"player": p.get("enemy"), "position": p.get("position")})
	# The soldier itself goes away soon; its gear is on the body now.
	var enemy := p.get("enemy") as Node
	if enemy != null:
		_grids.erase(int(enemy.get_meta(&"peer_id", 0)))


## Item ids for an enemy's pockets: a few rolls on the weighted loot table.
func _roll_loot() -> Array:
	return _roll(_data.get("npc_loot", {}))


## Server: everything the dead carried stays on their body where they fell, for anyone to
## search; a player comes back with an empty backpack.
func _on_player_died(p: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var player := p.get("player") as Node3D
	if player == null:
		return
	var peer := int(player.get_meta(&"peer_id", 1))
	var grid: InventoryGear = _grids.get(peer)
	if grid == null:
		return
	server_close(peer)
	var fresh := _new_grid()
	_wear(fresh, _data.get("respawn_gear", {}))
	if grid == _mine:
		_mine = fresh
	_grids[peer] = fresh
	var at: Vector3 = p.get("position", player.global_position)
	server_spawn_body(_on_ground(at), player.global_rotation.y, grid)
	_send(peer)


## Server: moves everything that fits out of `crate` into `peer`'s backpack, as "Take
## all" does. An emptied crate refills later.
func server_search(peer: int, crate: Node3D) -> int:
	var id := int(crate.get_meta(&"container", -1))
	var taken := _take_all(peer, id)
	_container_changed(id)
	return taken


## Item ids in a crate (or body), for tests and saving.
func crate_contents(crate: Node3D) -> Array:
	var grid := _grid_of_container(crate)
	var out := []
	if grid != null:
		for placed: Dictionary in grid.all_items():
			out.append(str(placed["item"]))
	return out


## Server: puts a crate on the ground with a roll of contents.
func server_spawn_crate(at: Vector3) -> LootCrate:
	_loot_count += 1
	var crate: LootCrate = _crate_spawner.spawn({"index": _loot_count, "position": at})
	var id := _new_container(crate, _crate_grid())
	_fill(_containers[id], _roll(_crates_data()))
	_crates.append(crate)
	return crate


## Server: a crate at `at` (the caller puts it on a floor) holding exactly `items` that never
## refills and is not saved with the world (a mission's objective, a building's loot). `server_remove_container` takes it away again.
func server_spawn_mission_crate(at: Vector3, items: Array) -> LootCrate:
	_loot_count += 1
	# Exactly where asked: a probe down from above would land it on a building's roof.
	var crate: LootCrate = _crate_spawner.spawn({"index": _loot_count, "position": at})
	crate.set_meta(&"no_refill", true)
	var id := _new_container(crate, _crate_grid())
	_fill(_containers[id], items)
	return crate


## A roll of crate loot (item ids) from the crate table, for crates other modules place.
func roll_crate_loot() -> Array:
	return _roll(_crates_data())


## Server: removes a crate or body and whatever is still in it.
func server_remove_container(node: Node) -> void:
	if node != null and node.has_meta(&"container"):
		_remove_container(int(node.get_meta(&"container")))


func _make_crate(data: Variant) -> Node:
	var info: Dictionary = data
	var crate := LootCrate.new()
	crate.name = "Crate%d" % int(info["index"])
	crate.position = info["position"]
	crate.rotation.y = float(int(info["index"]) * 53 % 360) * PI / 180.0
	return crate


## Server: lays a body on the ground holding `grid`; it goes away after a while, sooner once
## it is empty.
func server_spawn_body(at: Vector3, yaw: float, grid: InventoryGear) -> LootBody:
	_loot_count += 1
	var body: LootBody = _body_spawner.spawn({"index": _loot_count, "position": at, "yaw": yaw})
	var id := _new_container(body, grid)
	_body_left[id] = float(_bodies_data().get("seconds", 300.0))
	_container_changed(id)
	return body


func _make_body(data: Variant) -> Node:
	var info: Dictionary = data
	var body := LootBody.new()
	body.name = "Body%d" % int(info["index"])
	body.position = info["position"]
	body.rotation.y = float(info.get("yaw", 0.0))
	var c: Array = _bodies_data().get("colour", [0.3, 0.33, 0.26])
	body.colour = Color(float(c[0]), float(c[1]), float(c[2]))
	return body


func _on_container_state(p: Dictionary) -> void:
	var node := p.get("node") as Node
	if node != null and node.has_method(&"set_empty"):
		node.call(&"set_empty", bool(p.get("empty", false)))


## The grid of a crate or body, or null (on the server; clients only see an open one).
func _grid_of_container(node: Node) -> InventoryGear:
	if node == null:
		return null
	return _containers.get(int(node.get_meta(&"container", -1)))


func _new_container(node: Node, grid: InventoryGear) -> int:
	var id := _next_container
	_next_container += 1
	node.set_meta(&"container", id)
	_containers[id] = grid
	_container_nodes[id] = node
	return id


func _fill(grid: InventoryGear, items: Array) -> void:
	for item: Variant in items:
		if grid.insert(_next_uid, str(item))["ok"]:
			_next_uid += 1


## Puts gear on: `{slot: item id}`.
func _wear(gear: InventoryGear, worn: Dictionary) -> void:
	for slot: String in worn:
		if gear.place(_next_uid, str(worn[slot]), {"slot": slot}).is_empty():
			_next_uid += 1


## Server: after any change to a container: tells everyone whether it is empty now, starts or
## stops a crate's refill, hurries an emptied body along, and sends the new contents to
## everyone looking into it.
func _container_changed(id: int) -> void:
	var grid: InventoryGear = _containers.get(id)
	var node: Node = _container_nodes.get(id)
	if grid == null or not is_instance_valid(node):
		return
	var empty := grid.is_empty()
	if empty != bool(node.get_meta(&"empty", false)):
		Net.server_broadcast(&"inventory.container_state", {"node": node, "empty": empty})
	if node is LootCrate and not node.get_meta(&"no_refill", false):
		if not empty:
			_crate_refill.erase(node)
		elif not _crate_refill.has(node):
			_crate_refill[node] = float(_crates_data().get("refill_seconds", 120.0))
	elif empty and _body_left.has(id):
		_body_left[id] = minf(float(_body_left[id]), float(_bodies_data().get("empty_seconds", 30.0)))
	for peer: int in _viewers.keys():
		if int(_viewers[peer]) == id:
			_send_container(peer, false)


func _remove_container(id: int) -> void:
	for peer: int in _viewers.keys():
		if int(_viewers[peer]) == id:
			server_close(peer)
	var node: Node = _container_nodes.get(id)
	if is_instance_valid(node):
		node.queue_free()
	_containers.erase(id)
	_container_nodes.erase(id)
	_body_left.erase(id)


func _crates_data() -> Dictionary:
	return _data.get("crates", {})


func _bodies_data() -> Dictionary:
	return _data.get("bodies", {})


func _crate_grid() -> InventoryGear:
	var grid := InventoryGear.new()
	grid.setup(_defs, {"slots": {}, "fixed": {"crate": _crates_data().get("grid", [6, 4])}, "fill_order": ["crate"]})
	return grid


## Server: opens the loot screen on a crate or body for `peer`.
func server_open(peer: int, node: Node3D) -> bool:
	var id := int(node.get_meta(&"container", -1))
	if not _containers.has(id) or _grids.get(peer) == null:
		return false
	_viewers[peer] = id
	if _session(peer) == null:
		_viewers.erase(peer)
		return false
	_send_container(peer, true)
	EventBus.publish(&"inventory.loot_opened", {"peer": peer, "container": id})
	return true


## Server: closes `peer`'s loot screen (they asked, walked off, died, or it is gone).
func server_close(peer: int) -> void:
	if not _viewers.has(peer):
		return
	_viewers.erase(peer)
	if peer == multiplayer.get_unique_id():
		_loot_closed()
	elif multiplayer.get_peers().has(peer):
		_loot_closed.rpc_id(peer)


## Server: the grid `peer` has open, if they may still use it: it exists, they are alive and
## within reach of it. Null otherwise.
func _session(peer: int) -> InventoryGear:
	var id := int(_viewers.get(peer, -1))
	var grid: InventoryGear = _containers.get(id)
	var node := _container_nodes.get(id) as Node3D
	var player := _player_of(peer)
	if grid == null or not is_instance_valid(node) or player == null or player.get_meta(&"dead", false):
		return null
	if player.global_position.distance_to(node.global_position) > LOOT_REACH:
		return null
	return grid


func _send_container(peer: int, opening: bool) -> void:
	var id := int(_viewers.get(peer, -1))
	var grid: InventoryGear = _containers.get(id)
	if grid == null:
		return
	var body := _container_nodes.get(id) is LootBody
	var title := "BODY" if body else "CRATE"
	if peer == multiplayer.get_unique_id():
		_theirs = grid
		_theirs_title = title
		EventBus.publish(&"inventory.loot_changed", {"peer": peer, "opened": opening})
	elif multiplayer.get_peers().has(peer):
		_receive_container.rpc_id(peer, body, grid.snapshot(), title, opening)


@rpc("authority", "call_remote", "reliable")
func _receive_container(body: bool, snapshot: Dictionary, title: String, opening: bool) -> void:
	var grid := _new_grid() if body else _crate_grid()
	_apply_snapshot(grid, snapshot)
	_theirs = grid
	_theirs_title = title
	EventBus.publish(&"inventory.loot_changed", {"peer": multiplayer.get_unique_id(), "opened": opening})


@rpc("authority", "call_remote", "reliable")
func _loot_closed() -> void:
	_theirs = null
	_theirs_title = ""
	EventBus.publish(&"inventory.loot_closed", {"peer": multiplayer.get_unique_id()})


## The open body or crate's grid as this instance sees it, or null when none is open.
func loot_grid() -> InventoryGear:
	return _theirs


func loot_title() -> String:
	return _theirs_title


## Client: closes the loot screen.
func request_close_loot() -> void:
	if multiplayer.is_server():
		server_close(multiplayer.get_unique_id())
	else:
		_request_close_loot.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_close_loot() -> void:
	if multiplayer.is_server():
		server_close(multiplayer.get_remote_sender_id())


## Client: moves an item between this player's gear (`false`) and the open body or crate
## (`true`), to (x, y), maybe turned.
func request_transfer(from_theirs: bool, uid: int, to_theirs: bool, place: Dictionary) -> void:
	if multiplayer.is_server():
		server_transfer(multiplayer.get_unique_id(), from_theirs, uid, to_theirs, place)
	else:
		_request_transfer.rpc_id(1, from_theirs, uid, to_theirs, place)


@rpc("any_peer", "call_remote", "reliable")
func _request_transfer(from_theirs: bool, uid: int, to_theirs: bool, place: Dictionary) -> void:
	if multiplayer.is_server():
		server_transfer(multiplayer.get_remote_sender_id(), from_theirs, uid, to_theirs, place)


## Client: moves an item to the other side, into the first place it fits (Ctrl+click).
func request_quick_move(from_theirs: bool, uid: int) -> void:
	if multiplayer.is_server():
		server_quick_move(multiplayer.get_unique_id(), from_theirs, uid)
	else:
		_request_quick_move.rpc_id(1, from_theirs, uid)


@rpc("any_peer", "call_remote", "reliable")
func _request_quick_move(from_theirs: bool, uid: int) -> void:
	if multiplayer.is_server():
		server_quick_move(multiplayer.get_remote_sender_id(), from_theirs, uid)


## Client: takes everything that fits from the open body or crate.
func request_take_all() -> void:
	if multiplayer.is_server():
		server_take_all(multiplayer.get_unique_id())
	else:
		_request_take_all.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_take_all() -> void:
	if multiplayer.is_server():
		server_take_all(multiplayer.get_remote_sender_id())


## Server: one move between `peer`'s gear and what they have open (or within either). The
## first request for an item wins; a later one finds it gone and is refused. Everyone looking
## into the container sees the result, and a refused drag snaps back.
func server_transfer(peer: int, from_theirs: bool, uid: int, to_theirs: bool, place: Dictionary) -> bool:
	var mine: InventoryGear = _grids.get(peer)
	var theirs := _session(peer) if from_theirs or to_theirs else null
	var why := ""
	if mine == null:
		why = "no inventory"
	elif (from_theirs or to_theirs) and theirs == null:
		why = "nothing open in reach"
	else:
		var from := theirs if from_theirs else mine
		var to := theirs if to_theirs else mine
		why = from.transfer(uid, to, place)
	return _after_move(peer, uid, why, from_theirs or to_theirs)


## Server: moves an item to the other side into the first place it fits.
func server_quick_move(peer: int, from_theirs: bool, uid: int) -> bool:
	var mine: InventoryGear = _grids.get(peer)
	var theirs := _session(peer)
	var why := ""
	if mine == null or theirs == null:
		why = "nothing open in reach"
	elif from_theirs:
		why = theirs.transfer_anywhere(uid, mine)
	else:
		why = mine.transfer_anywhere(uid, theirs)
	return _after_move(peer, uid, why, true)


## Server: takes everything that fits from what `peer` has open.
func server_take_all(peer: int) -> int:
	if _session(peer) == null:
		_after_move(peer, -1, "nothing open in reach", true)
		return 0
	var id := int(_viewers[peer])
	var taken := _take_all(peer, id)
	_send(peer)
	_container_changed(id)
	return taken


func _take_all(peer: int, id: int) -> int:
	var mine: InventoryGear = _grids.get(peer)
	var theirs: InventoryGear = _containers.get(id)
	if mine == null or theirs == null:
		return 0
	var taken := 0
	for placed: Dictionary in theirs.all_items():
		if theirs.transfer_anywhere(int(placed["uid"]), mine).is_empty():
			taken += 1
	if taken > 0:
		EventBus.publish(&"inventory.loot_moved", {"peer": peer, "container": id, "uid": -1, "count": taken})
		_send(peer)
	return taken


func _after_move(peer: int, uid: int, why: String, touched_theirs: bool) -> bool:
	var id := int(_viewers.get(peer, -1))
	if why.is_empty():
		EventBus.publish(&"inventory.loot_moved", {"peer": peer, "container": id, "uid": uid, "count": 1})
	else:
		Log.info(&"inventory", "peer %d: loot move refused: %s" % [peer, why])
		EventBus.publish(&"inventory.loot_refused", {"peer": peer, "container": id, "uid": uid, "reason": why})
	_send(peer)
	if touched_theirs:
		if _session(peer) == null:
			server_close(peer)
		if _containers.has(id):
			_container_changed(id)
	return why.is_empty()


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
			var grid := _grid_of_container(crate)
			if grid != null and grid.is_empty():
				_fill(grid, _roll(_crates_data()))
			_container_changed(int(crate.get_meta(&"container", -1)))
	for id: int in _body_left.keys():
		_body_left[id] = float(_body_left[id]) - delta
		if float(_body_left[id]) <= 0.0:
			_remove_container(id)
	# Walking away from a body or crate (or dying) closes its loot screen.
	for peer: int in _viewers.keys():
		if _session(peer) == null:
			server_close(peer)


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
	_viewers.erase(peer)


## Server: a friend who joins late sees which crates are already emptied.
func _on_peer_joined(peer: int) -> void:
	if not multiplayer.is_server():
		return
	var emptied: Array[String] = []
	for node: Node in _container_nodes.values():
		if is_instance_valid(node) and node.get_meta(&"empty", false):
			emptied.append(String(node.name))
	if not emptied.is_empty():
		_receive_emptied.rpc_id(peer, emptied)


@rpc("authority", "call_remote", "reliable")
func _receive_emptied(names: Array) -> void:
	for crate_name: Variant in names:
		var node := get_node_or_null(NodePath(str(crate_name)))
		if node != null and node.has_method(&"set_empty"):
			node.call(&"set_empty", true)


## Server: `peer`'s gear as `[{item, container, x, y, rotated}]` for saving; a worn item's
## container is `slot:<name>`.
func server_items_of(peer: int) -> Array:
	var gear: InventoryGear = _grids.get(peer)
	var out := []
	if gear == null:
		return out
	for placed: Dictionary in gear.all_items():
		var container := "slot:%s" % placed["slot"] if placed.has("slot") else str(placed["grid"])
		out.append({"item": placed["item"], "container": container, "x": placed["x"], "y": placed["y"], "rotated": placed["rotated"]})
	return out


## Server: replaces `peer`'s gear with saved items, each where it was: worn items first, so
## their grids are open for what was inside. Anything that no longer fits there goes in the
## first free place, and what has no room at all lands at the player's feet rather than
## vanishing.
func server_restore_items(peer: int, items: Array) -> void:
	var grid := _new_grid()
	if peer == multiplayer.get_unique_id():
		_mine = grid
	_grids[peer] = grid
	var ordered := items.filter(func(i: Dictionary) -> bool: return str(i.get("container", "")).begins_with("slot:"))
	ordered.append_array(items.filter(func(i: Dictionary) -> bool: return not str(i.get("container", "")).begins_with("slot:")))
	var spilled: Array[String] = []
	for saved: Dictionary in ordered:
		var item := str(saved.get("item", ""))
		if item_info(item).is_empty():
			Log.warn(&"inventory", "peer %d: dropped unknown saved item '%s'" % [peer, item])
			continue
		var why := grid.place(_next_uid, item, _place_of(saved))
		if not why.is_empty() and not grid.insert(_next_uid, item)["ok"]:
			spilled.append(item)
			continue
		_next_uid += 1
	var player := _player_of(peer)
	for item in spilled:
		if player != null:
			server_spawn_loot(item, _on_ground(player.global_position))
	_send(peer)


## `{slot}` or `{grid, x, y, rotated}` from a saved or sent item.
static func _place_of(saved: Dictionary) -> Dictionary:
	var container := str(saved.get("container", ""))
	if container.begins_with("slot:"):
		return {"slot": container.trim_prefix("slot:")}
	return {"grid": container, "x": int(saved.get("x", 0)), "y": int(saved.get("y", 0)), "rotated": bool(saved.get("rotated", false))}


## Server: loose loot and crate state, for saving: `{loot: [{item, position}], crates:
## [{index, items, refill_seconds}]}`, refill_seconds -1 for a crate not waiting to refill.
func server_world_state() -> Dictionary:
	var loot := []
	for node: Node in get_tree().get_nodes_in_group(&"loot"):
		var item := node as LootItem
		if item != null and not item.is_queued_for_deletion():
			loot.append({"item": item.item, "position": item.global_position})
	# Bodies do not outlast a restart; what they held is saved as loot where they lie.
	for id: int in _body_left.keys():
		var body := _container_nodes.get(id) as Node3D
		var grid: InventoryGear = _containers.get(id)
		if not is_instance_valid(body) or grid == null:
			continue
		var items := grid.all_items()
		for i in items.size():
			var a := TAU * i / maxf(1.0, items.size())
			loot.append({"item": items[i]["item"], "position": body.global_position + Vector3(cos(a), 0.0, sin(a)) * PILE_RADIUS})
	var crates := []
	for i in _crates.size():
		var crate := _crates[i]
		if not is_instance_valid(crate):
			continue
		crates.append({"index": i, "items": crate_contents(crate), "refill_seconds": float(_crate_refill.get(crate, -1.0))})
	return {"loot": loot, "crates": crates}


## Server: puts the world back as saved: the loot on the ground replaces whatever this
## session laid out, and crates take back their contents and refill timers. Crates match by
## spawn order; extra saved ones (fewer crates now) are ignored.
func server_restore_world(state: Dictionary) -> void:
	for node: Node in get_tree().get_nodes_in_group(&"loot"):
		node.queue_free()
	for id: int in _body_left.keys():
		_remove_container(id)
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
		var grid := _grid_of_container(crate)
		if grid == null:
			continue
		for placed: Dictionary in grid.all_items():
			grid.remove(int(placed["uid"]))
		var items: Array = []
		for item: Variant in saved.get("items", []):
			if not item_info(str(item)).is_empty():
				items.append(str(item))
		_fill(grid, items)
		var refill := float(saved.get("refill_seconds", -1.0))
		if refill >= 0.0:
			_crate_refill[crate] = refill
		else:
			_crate_refill.erase(crate)
		_container_changed(int(crate.get_meta(&"container", -1)))


## A player's (or body's) gear, empty: the slots, pockets, and nothing worn.
func _new_grid() -> InventoryGear:
	var layout: Dictionary = _data.get("gear", {})
	var gear := InventoryGear.new()
	gear.setup(_defs, {"slots": layout.get("slots", {}), "fixed": {"pockets": layout.get("pockets", [4, 1])}, "fill_order": layout.get("fill_order", [])})
	return gear


## Rebuilds a copy of someone's gear from a `snapshot()`: worn items first, then the grids.
func _apply_snapshot(gear: InventoryGear, snapshot: Dictionary) -> void:
	var slots: Dictionary = snapshot.get("slots", {})
	for slot: String in slots:
		var worn: Dictionary = slots[slot]
		gear.place(int(worn["uid"]), str(worn["item"]), {"slot": slot})
	var grids: Dictionary = snapshot.get("grids", {})
	for name: String in grids:
		for placed: Dictionary in grids[name]:
			gear.place(int(placed["uid"]), str(placed["item"]), {"grid": name, "x": int(placed["x"]), "y": int(placed["y"]), "rotated": bool(placed["rotated"])})


## Server: sends `peer` their inventory. On the server's own player it is already current.
func _send(peer: int) -> void:
	if peer == multiplayer.get_unique_id():
		EventBus.publish(&"inventory.changed", {"peer": peer})
		return
	var grid: InventoryGear = _grids.get(peer)
	if grid != null and multiplayer.get_peers().has(peer):
		_receive.rpc_id(peer, grid.snapshot())
	EventBus.publish(&"inventory.changed", {"peer": peer})


@rpc("authority", "call_remote", "reliable")
func _receive(snapshot: Dictionary) -> void:
	_mine = _new_grid()
	_apply_snapshot(_mine, snapshot)
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
