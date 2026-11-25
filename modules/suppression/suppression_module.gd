extends Node
## Players pinned by fire (#547). The server counts rounds from anyone on another side that
## pass close to a player (the near-miss test soldiers use) and keeps each player's
## suppression (SuppressionLevel), which widens their own spread while it is up
## (`aim_spread_multiplier` on the player, read by their gun). Each near miss is sent to the
## owning client with the new value; that client follows the decay itself, darkens its screen
## edges and shakes its view (SuppressionView) and publishes `suppression.near_miss`
## ({position, level}) locally, for the crack where the round passed. A hit counts as a near
## miss too, as it does for soldiers; a round that goes on through a wall counts once.

const CONFIG := "res://modules/suppression/data/suppression.json"
const REQUIRED := {"near_miss_metres": TYPE_FLOAT, "chest_below_eyes": TYPE_FLOAT, "per_near_miss": TYPE_FLOAT,
	"decay_per_second": TYPE_FLOAT, "spread_penalty": TYPE_FLOAT, "vignette": TYPE_DICTIONARY, "shake": TYPE_DICTIONARY}

var config: Dictionary = {}

## Server: player -> their SuppressionLevel, for every player (not soldiers) spawned.
var _levels: Dictionary[PlayerController, SuppressionLevel] = {}
## Client: the local player's suppression as the server last sent it, decaying since.
var _local := SuppressionLevel.new()
var _local_player: PlayerController
var _view: SuppressionView
## Server: player -> [shooter, physics frame] of the last round counted, so the stretches of
## one round going through a wall (each its own `weapon.fired`, all in one frame) count once.
var _last_counted: Dictionary[PlayerController, Array] = {}


func _ready() -> void:
	var data: Variant = Data.load_json(CONFIG)
	if not (data is Dictionary and Data.require(CONFIG, data, REQUIRED)):
		set_process(false)
		set_physics_process(false)
		return
	config = data
	_local = SuppressionLevel.from_config(config)
	EventBus.subscribe(&"weapon.fired", _on_fired)
	EventBus.subscribe(&"player.spawned", _on_player_spawned)
	EventBus.subscribe(&"player.died", _on_player_died)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"weapon.fired", _on_fired)
	EventBus.unsubscribe(&"player.spawned", _on_player_spawned)
	EventBus.unsubscribe(&"player.died", _on_player_died)


## Server: `peer`'s suppression now, 0 to 1 (0 for nobody we know).
func level_of(peer: int) -> float:
	for player: PlayerController in _levels:
		if is_instance_valid(player) and int(player.get_meta(&"peer_id", 0)) == peer:
			return _levels[player].value
	return 0.0


## Client: this machine's player's suppression.
func local_level() -> float:
	return _local.value


func _physics_process(delta: float) -> void:
	if _levels.is_empty():
		return
	var prof := Prof.start()
	for player: PlayerController in _levels.keys():
		if not is_instance_valid(player):
			_levels.erase(player)
			_last_counted.erase(player)
			continue
		var level := _levels[player]
		level.tick(delta)
		player.aim_spread_multiplier = 1.0 + level.value * float(config["spread_penalty"])
	Prof.stop(&"suppression/server:physics", prof)


func _process(delta: float) -> void:
	_local.tick(delta)
	if _view != null:
		_view.level = _local.value


func _on_player_spawned(p: Dictionary) -> void:
	var player := p.get("player") as PlayerController
	if player == null:
		return
	if multiplayer.is_server() and not bool(p.get("npc", false)):
		if not _levels.has(player):
			# A kicked or leaving player is freed; a freed key in a typed loop logs an error (#587).
			player.tree_exiting.connect(_forget.bind(player), CONNECT_ONE_SHOT)
		_levels[player] = SuppressionLevel.from_config(config)
	if bool(p.get("local", false)):
		_local_player = player
		_local.reset()
		# A server (or any headless run) draws nothing.
		if DisplayServer.get_name() != "headless":
			_show_view(player)


func _forget(player: PlayerController) -> void:
	_levels.erase(player)
	_last_counted.erase(player)


func _show_view(player: PlayerController) -> void:
	if _view == null:
		_view = SuppressionView.new()
		_view.name = "View"
		_view.config = config
		add_child(_view)
	_view.camera = player.get_node_or_null("Head/Camera") as Camera3D
	_view.base_fov = float(player.config.get("fov", 80.0))


## Everywhere: death clears it, on the server and on the dead player's own screen. Nothing
## builds while dead (the body is out of the world until the respawn).
func _on_player_died(p: Dictionary) -> void:
	var player := p.get("player") as PlayerController
	if player == null:
		return
	if _levels.has(player):
		_levels[player].reset()
		player.aim_spread_multiplier = 1.0
	if player == _local_player:
		_local.reset()


## Server: every stretch of every round is checked against every player it could have passed.
## Rounds from your own side don't pin you: co-op partners firing past you, or yourself.
func _on_fired(p: Dictionary) -> void:
	if not multiplayer.is_server() or _levels.is_empty():
		return
	var shooter := p.get("holder") as Node
	if shooter == null or not is_instance_valid(shooter) or not (p.get("from") is Vector3 and p.get("to") is Vector3):
		return
	var from: Vector3 = p["from"]
	var to: Vector3 = p["to"]
	var reach := float(config["near_miss_metres"])
	var side := HitscanWeapon.team_of(shooter)
	var round_id := [shooter, Engine.get_physics_frames()]
	for player: PlayerController in _levels:
		# Parked in a car, the body waits unseen where they got in: rounds there miss nobody.
		if not is_instance_valid(player) or player == shooter or player.get_meta(&"dead", false) or player.process_mode == Node.PROCESS_MODE_DISABLED:
			continue
		if side == HitscanWeapon.team_of(player):
			continue
		var chest := chest_of(player)
		if SuppressionLevel.distance_to_segment(chest, from, to) >= reach:
			continue
		if bool(p.get("through", false)) and _last_counted.get(player, []) == round_id:
			continue
		_last_counted[player] = round_id
		var peer := int(player.get_meta(&"peer_id", 0))
		var level := _levels[player]
		level.add_near_miss()
		if peer != 0:
			_send(peer, level.value, SuppressionLevel.closest_on_segment(chest, from, to))


## Where near misses are measured from: under the eyes, so it follows a crouch.
func chest_of(player: PlayerController) -> Vector3:
	var head := player.get_node_or_null("Head") as Node3D
	var eyes := head.global_position if head != null else player.global_position + Vector3.UP * 1.65
	return eyes - Vector3.UP * float(config["chest_below_eyes"])


func _send(peer: int, value: float, near: Vector3) -> void:
	if multiplayer.get_peers().has(peer):
		_receive_near_miss.rpc_id(peer, value, near)
		NetStats.add(&"rpc/suppression", NetStats.size_of([value, near]))
	elif peer == multiplayer.get_unique_id():
		_receive_near_miss(value, near)


## Owning client: a round just went past at `near`; the server's value after it.
@rpc("authority", "call_remote", "reliable")
func _receive_near_miss(value: float, near: Vector3) -> void:
	_local.value = clampf(value, 0.0, 1.0)
	if _view != null:
		_view.level = _local.value
		_view.near_miss()
	EventBus.publish(&"suppression.near_miss", {"position": near, "level": _local.value})
