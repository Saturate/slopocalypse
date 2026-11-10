extends Node
## Keeps a stalker drone on the hunt: spawns one at a distance from a player once the world
## is ready, and sends a replacement a few seconds after each one goes down. Server only.
## Other modules (missions) send strike drones at spots through the `drones_api` group:
## `server_spawn_strike`, `strike_count`, `server_clear_strikes`.

const SCENE := "res://modules/drones/scenes/drone.tscn"
const CONFIG := "res://modules/drones/data/drones.json"
## A new drone appears this high over the ground (or its target, whichever is higher).
const SPAWN_HEIGHT := 20.0

var config: Dictionary = {}
var _players: Array[Node3D] = []
var _drones: Array[StalkerDrone] = []
var _respawn_in := -1.0
var _rng := RandomNumberGenerator.new()
var _spawner := MultiplayerSpawner.new()
var _spawned_count := 0
## Server: strike drones still flying.
var _strikes: Array[StalkerDrone] = []

## Kept loaded: Godot's resource cache lets go of a scene once nothing holds it, and loading
## a generated scene again from text costs tens of milliseconds per spawn.
var _packed_scene: PackedScene


func _scene() -> PackedScene:
	if _packed_scene == null:
		_packed_scene = load(SCENE)
	return _packed_scene


func _ready() -> void:
	# The server spawns drones; the spawner replicates them to clients.
	_spawner.name = "Spawner"
	_spawner.spawn_path = NodePath("..")
	_spawner.spawn_function = _spawn_drone
	add_child(_spawner)
	var data: Variant = Data.load_json(CONFIG)
	if not data is Dictionary or not Data.require(CONFIG, data, {"spawn_distance": TYPE_FLOAT, "respawn_seconds": TYPE_FLOAT, "max_drones": TYPE_FLOAT}):
		return
	config = data
	add_to_group(&"drones_api")
	EventBus.subscribe(&"player.spawned", _on_player_spawned)
	EventBus.subscribe(&"admin.spawn", _on_admin_spawn)
	EventBus.subscribe(&"weapon.fired", _on_weapon_fired)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"player.spawned", _on_player_spawned)
	EventBus.unsubscribe(&"admin.spawn", _on_admin_spawn)
	EventBus.unsubscribe(&"weapon.fired", _on_weapon_fired)


func drones() -> Array[StalkerDrone]:
	return _drones


func _on_player_spawned(p: Dictionary) -> void:
	_players.append(p["player"])
	if _drones.is_empty():
		_respawn_in = 1.0


func _physics_process(delta: float) -> void:
	var prof := Prof.start()
	_physics_tick(delta)
	Prof.stop(&"drones/module:physics", prof)


func _physics_tick(delta: float) -> void:
	if not multiplayer.is_server() or config.is_empty():
		return
	# Players who left are freed objects; a typed lambda can't even receive those.
	var alive: Array[Node3D] = []
	for n in _players:
		if is_instance_valid(n):
			alive.append(n)
	_players = alive
	if _respawn_in >= 0.0:
		_respawn_in -= delta
		if _respawn_in < 0.0 and _drones.size() < int(config["max_drones"]) and not _players.is_empty():
			server_spawn(_players[_rng.randi() % _players.size()])


## Server only: a new drone appears high up at spawn distance from `target` and hunts it.
func server_spawn(target: Node3D) -> StalkerDrone:
	var angle := _rng.randf() * TAU
	var distance: float = config["spawn_distance"]
	var at := target.global_position + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
	# High over the ground there, not over the target: the spot may be up a hillside.
	at.y = maxf(target.global_position.y, StalkerDrone.terrain_height(get_tree(), at)) + SPAWN_HEIGHT
	var drone: StalkerDrone = _spawner.spawn({"index": _spawned_count, "position": at})
	_spawned_count += 1
	drone.target = target
	drone.destroyed.connect(_on_drone_destroyed.bind(drone))
	_drones.append(drone)
	return drone


## Runs on the server and, through the spawner, on every client.
func _spawn_drone(data: Variant) -> Node:
	var info: Dictionary = data
	var drone: StalkerDrone = _scene().instantiate()
	drone.name = "Drone%d" % int(info["index"])
	drone.position = info["position"]
	return drone


func _on_drone_destroyed(drone: StalkerDrone) -> void:
	_drones.erase(drone)
	_respawn_in = config["respawn_seconds"]


## Server only: a strike drone sent at `point` on the ground; it comes in high from a
## distance and dives into the spot.
func server_spawn_strike(point: Vector3) -> StalkerDrone:
	var marker := Node3D.new()
	marker.name = "StrikePoint%d" % _spawned_count
	add_child(marker)
	marker.global_position = point
	var angle := _rng.randf() * TAU
	var distance: float = config["spawn_distance"]
	var at := point + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
	at.y = maxf(point.y, StalkerDrone.terrain_height(get_tree(), at)) + SPAWN_HEIGHT
	var drone: StalkerDrone = _spawner.spawn({"index": _spawned_count, "position": at})
	_spawned_count += 1
	drone.server_strike(marker)
	drone.destroyed.connect(_on_strike_destroyed.bind(drone))
	drone.damaged_by.connect(_on_strike_shot)
	_strikes.append(drone)
	return drone


func strike_count() -> int:
	return _strikes.size()


## Server only: calls off every strike drone (the mission is over).
func server_clear_strikes() -> void:
	for drone in _strikes:
		if is_instance_valid(drone):
			drone.queue_free()
	_strikes.clear()


func _on_strike_destroyed(drone: StalkerDrone) -> void:
	_strikes.erase(drone)


## Server: one strike drone was shot: the others near it turn on the shooter too.
func _on_strike_shot(shooter: Node3D, at: Vector3) -> void:
	_alert_strikes(shooter, at, float(config.get("strike_alert_radius", 30.0)))


## Server: shots fired near strike drones draw them to the shooter.
func _on_weapon_fired(p: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var shooter := p.get("holder") as Node3D
	if shooter != null and shooter.is_in_group(&"players"):
		_alert_strikes(shooter, shooter.global_position, float(config.get("strike_hear_radius", 25.0)))


func _alert_strikes(shooter: Node3D, at: Vector3, radius: float) -> void:
	if shooter == null:
		return
	for drone in _strikes:
		if is_instance_valid(drone) and not drone.downed and drone.global_position.distance_to(at) <= radius:
			drone.server_anger(shooter)


## Server: an admin asked for a drone; it comes for them.
func _on_admin_spawn(p: Dictionary) -> void:
	if p.get("kind") == "drone" and multiplayer.is_server() and p.get("player") is Node3D:
		server_spawn(p["player"])
