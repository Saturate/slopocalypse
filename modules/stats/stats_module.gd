extends Node
## Kill stats (#344): who killed what, per player by name, kept on the server, saved by
## persistence and shown in the Esc menu. Only recorded and shown for now; gameplay around
## them comes later. Fed by the death events that exist: enemy.died, player.died, drone.died
## (each names its source: the player whose round, rocket or charge did it) and
## weapon.headshot_kill. Other modules find it in the `stats_api` group.

var stats := KillStats.new()
## Client: this player's counts as the server last sent them.
var mine: Dictionary = {}

var _screen: StatsScreen


func _ready() -> void:
	add_to_group(&"stats_api")
	EventBus.subscribe(&"enemy.died", _on_enemy_died)
	EventBus.subscribe(&"player.died", _on_player_died)
	EventBus.subscribe(&"drone.died", _on_drone_died)
	EventBus.subscribe(&"civilian.died", _on_civilian_died)
	EventBus.subscribe(&"weapon.headshot_kill", _on_headshot)
	EventBus.subscribe(&"player.spawned", _on_player_spawned)
	if DisplayServer.get_name() != "headless":
		_screen = StatsScreen.new()
		_screen.name = "StatsScreen"
		_screen.stats_module = self
		add_child(_screen)
		_add_menu_entry.call_deferred()


func _exit_tree() -> void:
	EventBus.unsubscribe(&"enemy.died", _on_enemy_died)
	EventBus.unsubscribe(&"player.died", _on_player_died)
	EventBus.unsubscribe(&"drone.died", _on_drone_died)
	EventBus.unsubscribe(&"civilian.died", _on_civilian_died)
	EventBus.unsubscribe(&"weapon.headshot_kill", _on_headshot)
	EventBus.unsubscribe(&"player.spawned", _on_player_spawned)


func _add_menu_entry() -> void:
	var overlay := get_tree().get_first_node_in_group(&"session_overlay")
	if overlay != null and overlay.has_method(&"add_menu_entry"):
		overlay.call(&"add_menu_entry", &"Stats", "Stats", _screen.open)


## Server: `peer`'s counts, for the save.
func server_stats_of(peer: int) -> Dictionary:
	return stats.of(_key(peer))


## Server: puts back saved counts and tells the player.
func server_set_stats(peer: int, values: Dictionary) -> void:
	stats.set_of(_key(peer), values)
	_send(peer)


## Server: everyone's counts added up.
func server_totals() -> Dictionary:
	return stats.totals()


## Server: the `count` players with the most kills (KillStats.top), for the status page.
func server_top(count: int) -> Array[Dictionary]:
	return stats.top(count)


func _key(peer: int) -> String:
	var who := Net.identity_of(peer)
	return str(who["name"]) if who.has("name") else "peer:%d" % peer


static func _peer_of(node: Node) -> int:
	return int(node.get_meta(&"peer_id", 1))


## What a death's source was: a player, a soldier, a drone, or nothing we count.
static func kind_of(source: Node) -> String:
	if source == null or not is_instance_valid(source):
		return "other"
	if source.is_in_group(&"players"):
		return "player"
	if source.is_in_group(&"enemies"):
		return "soldier"
	# Duck-typed: the drones module can be deleted, so its class can't be named here.
	if source.has_method(&"server_crash"):
		return "drone"
	return "other"


func _killer_peer(source: Variant) -> int:
	var node := source as Node
	if node == null or not is_instance_valid(node) or not node.is_in_group(&"players"):
		return 0
	return _peer_of(node)


func _distance(a: Variant, b: Variant) -> float:
	if a is Node3D and b is Vector3 and is_instance_valid(a):
		return (a as Node3D).global_position.distance_to(b)
	return 0.0


func _on_enemy_died(p: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var peer := _killer_peer(p.get("source"))
	if peer == 0:
		return
	var enemy := p.get("enemy") as Node
	var faction := str(enemy.get_meta(&"faction", "")) if enemy != null else ""
	stats.record_kill(_key(peer), "soldier", faction, _distance(p.get("source"), p.get("position")))
	_send(peer)


func _on_player_died(p: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var victim := p.get("player") as Node
	if victim == null:
		return
	var source := p.get("source") as Node
	var kind := "self" if source == victim else kind_of(source)
	stats.record_death(_key(_peer_of(victim)), kind)
	_send(_peer_of(victim))
	var peer := _killer_peer(source)
	if peer != 0 and source != victim:
		stats.record_kill(_key(peer), "player", "", _distance(source, p.get("position")))
		_send(peer)


func _on_drone_died(p: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var peer := _killer_peer(p.get("source"))
	if peer == 0:
		return
	var drone := p.get("drone") as Node3D
	stats.record_kill(_key(peer), "drone", "", _distance(p.get("source"), drone.global_position if drone != null else null))
	_send(peer)


func _on_civilian_died(p: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var peer := _killer_peer(p.get("source"))
	if peer == 0:
		return
	stats.record_kill(_key(peer), "civilian", "", _distance(p.get("source"), p.get("position")))
	_send(peer)


func _on_headshot(p: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var peer := _killer_peer(p.get("holder"))
	if peer != 0:
		stats.add(_key(peer), "headshots")
		_send(peer)


func _on_player_spawned(p: Dictionary) -> void:
	if not multiplayer.is_server() or p.get("npc", false):
		return
	var player := p.get("player") as Node
	if player != null:
		_send.call_deferred(_peer_of(player))


func _send(peer: int) -> void:
	var values := stats.of(_key(peer))
	if multiplayer.get_peers().has(peer):
		_receive.rpc_id(peer, values)
	elif peer == multiplayer.get_unique_id():
		_receive(values)


@rpc("authority", "call_remote", "reliable")
func _receive(values: Dictionary) -> void:
	mine = values
