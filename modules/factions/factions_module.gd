extends Node
## Soldier factions (#343): their looks, gear and leanings, who is hostile to whom, and each
## player's standing with each faction (FactionRules). The server keeps the standing (by
## player name, saved by persistence) and sends each player theirs; soldiers shoot only the
## players they're hostile to. Other modules ask through the `factions_api` group and work
## without it (one side, "enemies", hostile to players only).

const CONFIG := "res://modules/factions/data/factions.json"
const REQUIRED := {"factions": TYPE_DICTIONARY, "relations": TYPE_ARRAY, "default_relation": TYPE_FLOAT, "hostile_below": TYPE_FLOAT, "guard_faction": TYPE_STRING}

var rules: FactionRules
## Client: this player's standing as the server last sent it, {faction: value}.
var my_standing: Dictionary = {}

var _screen: StandingScreen


func _ready() -> void:
	var data: Variant = Data.load_json(CONFIG)
	if not (data is Dictionary and Data.require(CONFIG, data, REQUIRED)):
		return
	rules = FactionRules.new(data)
	add_to_group(&"factions_api")
	EventBus.subscribe(&"enemy.died", _on_enemy_died)
	EventBus.subscribe(&"enemy.hurt", _on_enemy_hurt)
	EventBus.subscribe(&"player.spawned", _on_player_spawned)
	if DisplayServer.get_name() != "headless":
		_screen = StandingScreen.new()
		_screen.name = "StandingScreen"
		_screen.factions = self
		add_child(_screen)
		_add_menu_entry.call_deferred()


func _exit_tree() -> void:
	EventBus.unsubscribe(&"player.spawned", _on_player_spawned)
	EventBus.unsubscribe(&"enemy.died", _on_enemy_died)
	EventBus.unsubscribe(&"enemy.hurt", _on_enemy_hurt)


func hostile(a: String, b: String) -> bool:
	return rules.hostile(a, b)


func pick(rng: RandomNumberGenerator) -> String:
	return rules.pick(rng)


func info(id: String) -> Dictionary:
	return rules.info(id)


func guard_faction() -> String:
	return str(rules.data["guard_faction"])


## Client: "Standing" in the Esc menu, when there is one (a player at the keyboard).
func _add_menu_entry() -> void:
	var overlay := get_tree().get_first_node_in_group(&"session_overlay")
	if overlay != null and overlay.has_method(&"add_menu_entry"):
		overlay.call(&"add_menu_entry", &"Standing", "Standing", _screen.open)


## Whether soldiers of `faction` shoot `player` (a player node) on sight.
func hostile_to_player(faction: String, player: Node) -> bool:
	return rules.hostile_to_player(faction, key_of(player))


func band(value: float) -> String:
	return rules.band(value)


## The name standing is kept under: the player's chosen name, or their peer before they have
## one (tests, bots).
func key_of(player: Node) -> String:
	var peer := int(player.get_meta(&"peer_id", 1))
	var who := Net.identity_of(peer)
	return str(who["name"]) if who.has("name") else "peer:%d" % peer


func _peer_of(player: Node) -> int:
	return int(player.get_meta(&"peer_id", 1))


## Server: `peer`'s standing, for the save.
func server_standing_of(peer: int) -> Dictionary:
	return rules.standing_of(_key_of_peer(peer))


## Server: puts back a saved standing and tells the player.
func server_set_standing(peer: int, values: Dictionary) -> void:
	rules.set_standing_of(_key_of_peer(peer), values)
	_send(peer)


func _key_of_peer(peer: int) -> String:
	var who := Net.identity_of(peer)
	return str(who["name"]) if who.has("name") else "peer:%d" % peer


## Server: a joining player hears their standing (persistence puts a saved one back after).
func _on_player_spawned(p: Dictionary) -> void:
	if not multiplayer.is_server() or p.get("npc", false):
		return
	var player := p.get("player") as Node
	if player != null:
		_send.call_deferred(_peer_of(player))


## Server: a soldier died; if a player killed it, their standing moves.
func _on_enemy_died(p: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var source := p.get("source") as Node
	var enemy := p.get("enemy") as Node
	if source == null or enemy == null or not is_instance_valid(source) or not source.is_in_group(&"players"):
		return
	rules.record_kill(key_of(source), str(enemy.get_meta(&"faction", "")))
	_send(_peer_of(source))


func _on_enemy_hurt(p: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var source := p.get("source") as Node
	var enemy := p.get("enemy") as Node
	if source == null or enemy == null or not is_instance_valid(source) or not source.is_in_group(&"players"):
		return
	rules.record_hurt(key_of(source), str(enemy.get_meta(&"faction", "")))
	_send(_peer_of(source))


func _send(peer: int) -> void:
	var values := rules.standing_of(_key_of_peer(peer))
	if multiplayer.get_peers().has(peer):
		_receive_standing.rpc_id(peer, values)
	elif peer == multiplayer.get_unique_id():
		_receive_standing(values)


@rpc("authority", "call_remote", "reliable")
func _receive_standing(values: Dictionary) -> void:
	my_standing = values
	EventBus.publish(&"factions.standing_changed", {"standing": values})
