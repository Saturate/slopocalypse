extends Node
## The admin panel's server side. Admins are whoever plays on the server's own machine (solo
## and the host) and anyone listed in data/admin.json `admins` by name or player key. A
## client asks through `request`; the server checks, logs, and hands the work to the module
## that owns it over the event bus (`admin.set_hour`, `admin.teleport`, `admin.spawn`),
## so any of those modules can be switched off. Heal and god mode act on the player's
## HealthComponent directly.

const CONFIG := "res://modules/admin/data/admin.json"
const REQUIRED := {
	"admins": TYPE_ARRAY,
	"local_is_admin": TYPE_BOOL,
	"toggle_key": TYPE_STRING,
	"spawn_ahead": TYPE_FLOAT,
	"teleport_ahead": TYPE_FLOAT,
	"squad_size": TYPE_FLOAT,
	"hours": TYPE_ARRAY,
}
const SPAWN_KINDS: Array[String] = ["drone", "squad", "crate", "loot", "car"]
## A teleport lands this far beside a car or another player, not inside them.
const BESIDE := 2.5

## Signals for the client's panel.
signal status_changed(admin: bool)
signal players_changed(names: Dictionary)
signal god_changed(on: bool)

var config: Dictionary = {}
## Client: whether the server says we are an admin.
var is_admin_here := false

var _panel: Node


func _ready() -> void:
	var data: Variant = Data.load_json(CONFIG)
	if not data is Dictionary or not Data.require(CONFIG, data, REQUIRED):
		return
	config = data
	Net.peer_joined.connect(_on_peers_changed)
	Net.peer_left.connect(_on_peers_changed)
	if DisplayServer.get_name() != "headless":
		_panel = (load("res://modules/admin/scripts/admin_panel.gd") as GDScript).new()
		_panel.name = "Panel"
		_panel.set(&"admin", self)
		add_child(_panel)


func _exit_tree() -> void:
	if Net.peer_joined.is_connected(_on_peers_changed):
		Net.peer_joined.disconnect(_on_peers_changed)
	if Net.peer_left.is_connected(_on_peers_changed):
		Net.peer_left.disconnect(_on_peers_changed)


## Server: may this peer use the panel?
func is_admin(peer: int) -> bool:
	# The server itself (tests and tools run with the offline peer as 1).
	if peer <= 1:
		return true
	if bool(config.get("local_is_admin", false)) and _is_local(peer):
		return true
	var who := Net.identity_of(peer)
	var listed: Array = config.get("admins", [])
	return not who.is_empty() and (listed.has(who.get("name", "")) or listed.has(who.get("key", "")))


func _is_local(peer: int) -> bool:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return false
	var remote := enet.get_peer(peer)
	return remote != null and remote.get_remote_address() in ["127.0.0.1", "::1", "::ffff:127.0.0.1"]


## Client -> server.
@rpc("any_peer", "call_remote", "reliable")
func request(action: String, args: Dictionary) -> void:
	if multiplayer.is_server():
		server_run(multiplayer.get_remote_sender_id(), action, args)


## Client: asks the server, or runs it here when this instance is the server.
func ask(action: String, args: Dictionary = {}) -> void:
	if multiplayer.is_server():
		server_run(1, action, args)
	else:
		request.rpc_id(1, action, args)


## Server: does `action` for `peer` if they are an admin. False when refused.
func server_run(peer: int, action: String, args: Dictionary) -> bool:
	var who := _name_of(peer)
	if not is_admin(peer):
		Log.warn(&"admin", "%s is not an admin; refused %s" % [who, action])
		return false
	var player := _player_of(peer)
	Log.info(&"admin", "%s: %s %s" % [who, action, args])
	match action:
		"hour":
			EventBus.publish(&"admin.set_hour", {"hour": float(args.get("hour", 12.0))})
		"heal":
			var health := _health(player)
			if health == null or health.is_dead():
				return false
			health.server_reset()
		"god":
			var health := _health(player)
			if health == null:
				return false
			health.invulnerable = bool(args.get("on", false))
			if peer > 1:
				_god_state.rpc_id(peer, health.invulnerable)
			else:
				god_changed.emit(health.invulnerable)
		"teleport":
			var to: Variant = _teleport_target(player, str(args.get("to", "")))
			if player == null or not to is Vector3:
				return false
			EventBus.publish(&"admin.teleport", {"player": player, "position": to})
		"spawn":
			var kind := str(args.get("kind", ""))
			if player == null or not SPAWN_KINDS.has(kind):
				return false
			EventBus.publish(&"admin.spawn", {"kind": kind, "player": player, "position": _ahead(player, float(config["spawn_ahead"])), "forward": _forward(player), "count": int(config["squad_size"])})
		_:
			Log.warn(&"admin", "unknown action %s" % action)
			return false
	return true


func _teleport_target(player: Node3D, to: String) -> Variant:
	if player == null:
		return null
	if to == "spawn":
		var spawn := get_tree().get_first_node_in_group(&"spawn_point") as Node3D
		return spawn.global_position if spawn != null else null
	if to == "ahead":
		return _ahead(player, float(config["teleport_ahead"])) + Vector3.UP
	if to == "car":
		var car := get_tree().get_first_node_in_group(&"vehicles") as Node3D
		return _beside(car)
	if to.begins_with("player:"):
		return _beside(_player_of(int(to.trim_prefix("player:"))))
	return null


func _beside(node: Node3D) -> Variant:
	if node == null:
		return null
	var at := node.global_position + node.global_transform.basis.x.normalized() * BESIDE
	return Vector3(at.x, _ground(at) + 1.0, at.z)


func _forward(player: Node3D) -> Vector3:
	var f := -player.global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.01 else Vector3.FORWARD


## On the ground `distance` in front of the player.
func _ahead(player: Node3D, distance: float) -> Vector3:
	var at := player.global_position + _forward(player) * distance
	return Vector3(at.x, _ground(at), at.z)


func _ground(at: Vector3) -> float:
	var ground := get_tree().get_first_node_in_group(&"ground")
	return float(ground.call(&"ground_height", at.x, at.z)) if ground != null else at.y


func _player_of(peer: int) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		if int(node.get_meta(&"peer_id", 0)) == peer:
			return node as Node3D
	return null


func _health(player: Node) -> HealthComponent:
	return player.get_node_or_null("Health") as HealthComponent if player != null else null


func _name_of(peer: int) -> String:
	return str(Net.identity_of(peer).get("name", "peer %d" % peer))


## Server: tells every peer whether they are an admin, and admins who is on, whenever
## someone comes or goes.
func _on_peers_changed(_peer: int) -> void:
	if not multiplayer.is_server():
		return
	var names := {}
	for peer in multiplayer.get_peers():
		if not Net.identity_of(peer).is_empty():
			names[peer] = _name_of(peer)
	for peer: int in names:
		var admin := is_admin(peer)
		_status.rpc_id(peer, admin, names if admin else {})


@rpc("authority", "call_remote", "reliable")
func _status(admin: bool, names: Dictionary) -> void:
	is_admin_here = admin
	status_changed.emit(admin)
	players_changed.emit(names)


@rpc("authority", "call_remote", "reliable")
func _god_state(on: bool) -> void:
	god_changed.emit(on)
