extends Node
## Owns the players. The server spawns one per peer through a MultiplayerSpawner, which
## replicates them to every client; each instance then wires input, camera and first-person
## view to its own player only. Solo is the same path with this instance as peer 1.
## Also parks a player while they drive (the car module decides) and rescues anyone who
## falls out of the world.

const SCENE := "res://modules/player/scenes/player.tscn"

var _spawner := MultiplayerSpawner.new()
var _players: Dictionary[int, PlayerController] = {}
var _spawn := Vector3.ZERO
var _kill_y := -INF
var _world_ready := false


func _ready() -> void:
	_spawner.name = "Spawner"
	_spawner.spawn_path = NodePath("..")
	_spawner.spawn_function = _spawn_player
	add_child(_spawner)
	EventBus.subscribe(&"world.ready", _on_world_ready)
	EventBus.subscribe(&"car.entered", _on_car_entered)
	EventBus.subscribe(&"car.exited", _on_car_exited)
	Net.peer_joined.connect(_on_peer_joined)
	Net.peer_left.connect(_on_peer_left)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"world.ready", _on_world_ready)
	EventBus.unsubscribe(&"car.entered", _on_car_entered)
	EventBus.unsubscribe(&"car.exited", _on_car_exited)


func players() -> Array[PlayerController]:
	var out: Array[PlayerController] = []
	out.assign(_players.values())
	return out


func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server():
		return
	# Safety net: anyone who falls out of the world is put back at the spawn.
	for player: PlayerController in _players.values():
		if player.global_position.y < _kill_y:
			Log.warn(&"player", "fell out of the world at %s, respawning" % player.global_position)
			player.global_position = _spawn
			player.velocity = Vector3.ZERO


func _on_world_ready(payload: Dictionary) -> void:
	_spawn = payload["spawn"]
	_kill_y = payload.get("kill_y", -INF)
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


func _on_player_ready(player: PlayerController, local: bool) -> void:
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
