extends Node
## Owns the players. The server spawns one per peer through a MultiplayerSpawner, which
## replicates them to every client; each instance then wires input, camera and first-person
## view to its own player only. Solo is the same path with this instance as peer 1.
## Also parks a player while they drive (the car module decides) and rescues anyone who
## falls out of the world.

const SCENE := "res://modules/player/scenes/player.tscn"
## How far down a held player looks for ground before letting go.
const GROUND_PROBE := 40.0

var _spawner := MultiplayerSpawner.new()
var _players: Dictionary[int, PlayerController] = {}
var _spawn := Vector3.ZERO
var _kill_y := -INF
## How far under the untouched ground (digging can't go this deep) counts as fallen through.
var _rescue_depth := INF
var _world_ready := false
## Server: players held still until there is ground under them -> seconds left to wait.
var _holding: Dictionary = {}
## Server: dead player -> seconds until they come back.
var _respawn_in: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_spawner.name = "Spawner"
	_spawner.spawn_path = NodePath("..")
	_spawner.spawn_function = _spawn_player
	add_child(_spawner)
	EventBus.subscribe(&"world.ready", _on_world_ready)
	EventBus.subscribe(&"car.entered", _on_car_entered)
	EventBus.subscribe(&"car.exited", _on_car_exited)
	EventBus.subscribe(&"player.died", _on_player_died)
	EventBus.subscribe(&"player.respawned", _on_player_respawned)
	Net.peer_joined.connect(_on_peer_joined)
	Net.peer_left.connect(_on_peer_left)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"world.ready", _on_world_ready)
	EventBus.unsubscribe(&"car.entered", _on_car_entered)
	EventBus.unsubscribe(&"car.exited", _on_car_exited)
	EventBus.unsubscribe(&"player.died", _on_player_died)
	EventBus.unsubscribe(&"player.respawned", _on_player_respawned)


func players() -> Array[PlayerController]:
	var out: Array[PlayerController] = []
	out.assign(_players.values())
	return out


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	for player: PlayerController in _respawn_in.keys():
		if not is_instance_valid(player):
			_respawn_in.erase(player)
			continue
		_respawn_in[player] = float(_respawn_in[player]) - delta
		if float(_respawn_in[player]) <= 0.0:
			server_respawn(player)
	_release_grounded(delta)
	# Safety net: anyone who slips under the terrain is lifted back on top where they were and
	# held there until its collision is in. Parked, held and dead players don't move.
	for player: PlayerController in _players.values():
		if not player.is_physics_processing() or not player.can_process():
			continue
		var at := player.global_position
		var ground := _ground_height(at)
		if at.y < ground - _rescue_depth or at.y < _kill_y:
			Log.warn(&"player", "fell through the ground at %s, putting them back on top" % at)
			player.global_position = Vector3(at.x, ground + 1.0, at.z)
			player.velocity = Vector3.ZERO
			server_hold(player)


## Server: freezes a player in place until a ray finds ground under them (or `hold_seconds`
## pass), so nobody drops through terrain whose collision is still being built.
func server_hold(player: PlayerController) -> void:
	player.set_physics_process(false)
	_holding[player] = float(player.config.get("hold_seconds", 10.0))


func _release_grounded(delta: float) -> void:
	for player: PlayerController in _holding.keys():
		if not is_instance_valid(player):
			_holding.erase(player)
			continue
		_holding[player] = float(_holding[player]) - delta
		if _has_ground(player) or float(_holding[player]) <= 0.0:
			_holding.erase(player)
			if not player.get_meta(&"dead", false):
				player.set_physics_process(true)


func _has_ground(player: PlayerController) -> bool:
	var at := player.global_position
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP, at + Vector3.DOWN * GROUND_PROBE)
	query.exclude = [player.get_rid()]
	return not player.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## The untouched ground under a point, from the world's height function (it answers even
## where no terrain is loaded); the spawn height when there is no world.
func _ground_height(at: Vector3) -> float:
	var ground := get_tree().get_first_node_in_group(&"ground")
	if ground == null:
		return _spawn.y
	return float(ground.call(&"ground_height", at.x, at.z))


func _on_world_ready(payload: Dictionary) -> void:
	_spawn = payload["spawn"]
	_kill_y = payload.get("kill_y", -INF)
	_rescue_depth = payload.get("rescue_depth", INF)
	_world_ready = true
	if not multiplayer.is_server():
		return
	if Net.has_local_player():
		_server_spawn(Net.local_peer_id())
	for peer in multiplayer.get_peers():
		_server_spawn(peer)


func _on_peer_joined(peer: int) -> void:
	if multiplayer.is_server() and _world_ready:
		_server_spawn(peer)


func _on_peer_left(peer: int) -> void:
	if multiplayer.is_server() and _players.has(peer):
		# Freeing the node makes the spawner remove it on every client.
		_players[peer].queue_free()
		_players.erase(peer)


## Server only.
func _server_spawn(peer: int) -> void:
	if _players.has(peer):
		return
	_spawner.spawn({"peer": peer, "position": _spawn})


## Runs on the server and, through the spawner, on every client.
func _spawn_player(data: Variant) -> Node:
	var info: Dictionary = data
	var peer: int = info["peer"]
	var player: PlayerController = (load(SCENE) as PackedScene).instantiate()
	player.name = str(peer)
	player.position = info["position"]
	player.set_meta(&"peer_id", peer)
	player.add_to_group(&"players")
	_players[peer] = player
	# The server simulates every player; client copies wait for movement sync (#10).
	if not multiplayer.is_server():
		player.set_physics_process(false)
	var local := Net.has_local_player() and peer == Net.local_peer_id()
	player.ready.connect(_on_player_ready.bind(player, local), CONNECT_ONE_SHOT)
	return player


## Server: a player's health ran out. Everyone sees them go down; they come back at the
## spawn after `respawn_seconds`. Other modules react to `player.died` (the inventory drops
## the backpack).
func _server_died(source: Node, player: PlayerController) -> void:
	if player.get_meta(&"dead", false):
		return
	Net.server_broadcast(&"player.died", {"player": player, "source": source, "position": player.global_position})
	_respawn_in[player] = float(player.config.get("respawn_seconds", 5.0))


## Server: brings a dead player back at full health near the spawn.
func server_respawn(player: PlayerController) -> void:
	_respawn_in.erase(player)
	(player.get_node("Health") as HealthComponent).server_reset()
	var spread := float(player.config.get("respawn_spread", 0.0))
	player.global_position = _spawn + Vector3(_rng.randf_range(-spread, spread), 0.5, _rng.randf_range(-spread, spread))
	player.velocity = Vector3.ZERO
	Net.server_broadcast(&"player.respawned", {"player": player})
	server_hold(player)


## Everywhere: a dead player is hidden, cannot be hit and does not move; the camera stays
## where they fell.
func _on_player_died(p: Dictionary) -> void:
	var player := p.get("player") as PlayerController
	if player != null:
		_set_dead(player, true)


func _on_player_respawned(p: Dictionary) -> void:
	var player := p.get("player") as PlayerController
	if player != null:
		_set_dead(player, false)


func _set_dead(player: PlayerController, dead: bool) -> void:
	player.set_meta(&"dead", dead)
	(player.get_node("Body") as Node3D).visible = not dead
	(player.get_node("Shape") as CollisionShape3D).set_deferred(&"disabled", dead)
	if multiplayer.is_server():
		player.set_physics_process(not dead)


func _on_player_ready(player: PlayerController, local: bool) -> void:
	if multiplayer.is_server():
		var health := player.get_node_or_null("Health") as HealthComponent
		if health != null:
			health.died.connect(_server_died.bind(player))
	# Other modules (weapons, world viewer, later inventory) equip players through this.
	EventBus.publish(&"player.spawned", {"player": player, "local": local})
	var bot := _bot_behaviour()
	if local and bot in PlayerBot.BEHAVIOURS:
		var driver := PlayerBot.new()
		driver.name = "Bot"
		driver.player = player
		driver.behaviour = bot
		player.add_child(driver)
	if DisplayServer.get_name() == "headless":
		return
	var animator := PlayerBodyAnimator.new()
	animator.name = "BodyAnimator"
	animator.player = player
	player.add_child(animator)
	if local:
		_setup_local(player)


func _setup_local(player: PlayerController) -> void:
	InputBindings.register(player.config.get("bindings", {}), &"player")
	var hud := PlayerHud.new()
	hud.name = "Hud"
	hud.player = player
	player.add_child(hud)
	var input := PlayerInput.new()
	input.name = "Input"
	input.intent = player.intent()
	input.player = player
	input.sensitivity = player.config["mouse_sensitivity"]
	player.add_child(input)
	var feel := PlayerCameraFeel.new()
	feel.name = "CameraFeel"
	feel.player = player
	feel.camera = _camera(player)
	player.add_child(feel)
	_camera(player).current = true
	# The camera sits inside the head: the torso only casts its shadow, while the player's
	# own arms and rifle stay in view.
	PlayerBody.first_person(player.get_node("Body"))


func _on_car_entered(payload: Dictionary) -> void:
	var player := payload.get("player") as PlayerController
	if player == null or not _players.values().has(player):
		return
	# Parked, not freed: the same player comes back on exit.
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.visible = false
	(player.get_node("Shape") as CollisionShape3D).set_deferred(&"disabled", true)


func _on_car_exited(payload: Dictionary) -> void:
	var player := payload.get("player") as PlayerController
	if player == null or not _players.values().has(player):
		return
	player.global_position = payload["position"]
	player.velocity = Vector3.ZERO
	player.process_mode = Node.PROCESS_MODE_INHERIT
	player.visible = true
	(player.get_node("Shape") as CollisionShape3D).set_deferred(&"disabled", false)
	var peer: int = player.get_meta(&"peer_id", 0)
	if DisplayServer.get_name() != "headless" and Net.has_local_player() and peer == Net.local_peer_id():
		_camera(player).current = true


## `--bot=NAME` after `--` makes this instance's own player drive itself (tests, soak).
func _bot_behaviour() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bot="):
			return arg.trim_prefix("--bot=")
	return ""


func _camera(player: PlayerController) -> Camera3D:
	return player.get_node("Head/Camera")
