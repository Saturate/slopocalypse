extends Node
## The trader at home base: a stall in the start tunnel. F at it opens the trade screen:
## buy from the stock for tokens (it goes into your gear if it fits), sell anything you
## carry for a share of its price. The server decides every trade; tokens live with the
## missions module (`missions_api`), gear with the inventory (`inventory_api`).

const CONFIG := "res://modules/trader/data/trader.json"
const REQUIRED := {"stall": TYPE_DICTIONARY, "reach": TYPE_FLOAT, "sell_share": TYPE_FLOAT, "unlisted_price": TYPE_FLOAT, "stock": TYPE_ARRAY}
## How squarely you must face the stall to use it.
const FACING := 0.6

var config: Dictionary = {}
var _stall: TraderStall


func _ready() -> void:
	add_to_group(&"trader_api")
	var parsed: Variant = Data.load_json(CONFIG)
	if not parsed is Dictionary or not Data.require(CONFIG, parsed, REQUIRED):
		return
	config = parsed
	EventBus.subscribe(&"world.ready", _on_world_ready)
	EventBus.subscribe(&"player.interact", _on_player_interact)
	EventBus.subscribe(&"player.spawned", _on_player_spawned)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"world.ready", _on_world_ready)
	EventBus.unsubscribe(&"player.interact", _on_player_interact)
	EventBus.unsubscribe(&"player.spawned", _on_player_spawned)


## The stock: `[{item, price}]`.
func stock() -> Array:
	return config.get("stock", [])


## What an item costs at the stall (its stock price, or `unlisted_price`).
func price_of(item: String) -> int:
	for entry: Dictionary in stock():
		if str(entry["item"]) == item:
			return int(entry["price"])
	return int(config.get("unlisted_price", 10))


## What the trader pays for an item.
func sell_price(item: String) -> int:
	return maxi(1, int(round(price_of(item) * float(config.get("sell_share", 0.5)))))


func _on_world_ready(payload: Dictionary) -> void:
	var spawn: Vector3 = payload.get("spawn", Vector3.ZERO)
	var o: Array = (config["stall"] as Dictionary).get("offset", [0.0, 0.0, 0.0])
	_stall = TraderStall.new()
	_stall.name = "TraderStall"
	add_child(_stall)
	# The spawn marker floats a metre over the floor.
	_stall.global_position = Vector3(spawn.x + float(o[0]), spawn.y - 1.0 + float(o[1]), spawn.z + float(o[2]))
	_stall.rotation.y = PI / 2.0 if float(o[0]) > 0.0 else -PI / 2.0


## Whether `player` is at the stall and facing it.
func at_stall(player: Node3D) -> bool:
	if _stall == null:
		return false
	var head := player.get_node_or_null("Head/Camera") as Node3D
	var eye := head.global_position if head != null else player.global_position + Vector3.UP * 1.6
	var forward := -head.global_transform.basis.z if head != null else -player.global_transform.basis.z
	var to := _stall.global_position + Vector3.UP * 1.1 - eye
	return to.length() < float(config.get("reach", 3.0)) + 1.0 and forward.dot(to.normalized()) > FACING


## Server: within reach of the stall (trades are refused from further away).
func _near(player: Node3D) -> bool:
	return _stall != null and player != null and player.global_position.distance_to(_stall.global_position) < float(config.get("reach", 3.0)) + 2.0


func _on_player_interact(payload: Dictionary) -> void:
	if not multiplayer.is_server() or payload.get("handled", false):
		return
	var player := payload["player"] as Node3D
	if not at_stall(player):
		return
	payload["handled"] = true
	var peer := int(player.get_meta(&"peer_id", 1))
	if peer == multiplayer.get_unique_id():
		EventBus.publish(&"trader.opened", {"peer": peer})
	elif multiplayer.get_peers().has(peer):
		_open.rpc_id(peer)


@rpc("authority", "call_remote", "reliable")
func _open() -> void:
	EventBus.publish(&"trader.opened", {"peer": multiplayer.get_unique_id()})


## Client: buys one `item` from the stock.
func request_buy(item: String) -> void:
	if multiplayer.is_server():
		server_buy(multiplayer.get_unique_id(), item)
	else:
		_request_buy.rpc_id(1, item)


@rpc("any_peer", "call_remote", "reliable")
func _request_buy(item: String) -> void:
	if multiplayer.is_server():
		server_buy(multiplayer.get_remote_sender_id(), item)


## Client: sells the item `uid` from this player's gear.
func request_sell(uid: int) -> void:
	if multiplayer.is_server():
		server_sell(multiplayer.get_unique_id(), uid)
	else:
		_request_sell.rpc_id(1, uid)


@rpc("any_peer", "call_remote", "reliable")
func _request_sell(uid: int) -> void:
	if multiplayer.is_server():
		server_sell(multiplayer.get_remote_sender_id(), uid)


## Server: one `item` for its price, if it is in stock, `peer` is at the stall, has the
## tokens and room for it. Refusals say why on the event bus.
func server_buy(peer: int, item: String) -> bool:
	var missions := get_tree().get_first_node_in_group(&"missions_api")
	var inventory := get_tree().get_first_node_in_group(&"inventory_api")
	var why := ""
	if missions == null or inventory == null:
		why = "no trading here"
	elif not stock().any(func(e: Dictionary) -> bool: return str(e["item"]) == item):
		why = "not in stock"
	elif not _near(_player_of(peer)):
		why = "not at the stall"
	elif int(missions.call(&"server_tokens_of", peer)) < price_of(item):
		why = "not enough tokens"
	elif not inventory.call(&"server_give", peer, item):
		why = "no room"
	if not why.is_empty():
		EventBus.publish(&"trader.refused", {"peer": peer, "item": item, "reason": why})
		return false
	missions.call(&"server_set_tokens", peer, int(missions.call(&"server_tokens_of", peer)) - price_of(item))
	EventBus.publish(&"trader.bought", {"peer": peer, "item": item, "tokens": price_of(item)})
	return true


## Server: takes the item `uid` from `peer`'s gear and pays its sell price.
func server_sell(peer: int, uid: int) -> bool:
	var missions := get_tree().get_first_node_in_group(&"missions_api")
	var inventory := get_tree().get_first_node_in_group(&"inventory_api")
	if missions == null or inventory == null or not _near(_player_of(peer)):
		EventBus.publish(&"trader.refused", {"peer": peer, "uid": uid, "reason": "not at the stall"})
		return false
	var item := str(inventory.call(&"server_take_uid", peer, uid))
	if item.is_empty():
		EventBus.publish(&"trader.refused", {"peer": peer, "uid": uid, "reason": "cannot sell that"})
		return false
	var pay := sell_price(item)
	missions.call(&"server_set_tokens", peer, int(missions.call(&"server_tokens_of", peer)) + pay)
	EventBus.publish(&"trader.sold", {"peer": peer, "item": item, "tokens": pay})
	return true


func _player_of(peer: int) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		if int(node.get_meta(&"peer_id", 1)) == peer:
			return node as Node3D
	return null


## Client only: the local player's prompt and trade screen.
func _on_player_spawned(p: Dictionary) -> void:
	if DisplayServer.get_name() == "headless" or not p.get("local", false):
		return
	var prompt := TraderPrompt.new()
	prompt.name = "TraderPrompt"
	prompt.trader = self
	prompt.player = p["player"] as Node3D
	add_child(prompt)
	var screen := TraderScreen.new()
	screen.name = "TraderScreen"
	screen.trader = self
	screen.peer = int((p["player"] as Node).get_meta(&"peer_id", 1))
	add_child(screen)
