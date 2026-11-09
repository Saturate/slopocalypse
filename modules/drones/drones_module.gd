extends Node
## Keeps a stalker drone on the hunt: spawns one at a distance from a player once the world
## is ready, and sends a replacement a few seconds after each one goes down. Server only.

const SCENE := "res://modules/drones/scenes/drone.tscn"
const CONFIG := "res://modules/drones/data/drones.json"

var config: Dictionary = {}
var _players: Array[Node3D] = []
var _drones: Array[StalkerDrone] = []
var _respawn_in := -1.0
var _rng := RandomNumberGenerator.new()
var _spawner := MultiplayerSpawner.new()
var _spawned_count := 0

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
	EventBus.subscribe(&"player.spawned", _on_player_spawned)
	EventBus.subscribe(&"admin.spawn", _on_admin_spawn)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"player.spawned", _on_player_spawned)
	EventBus.unsubscribe(&"admin.spawn", _on_admin_spawn)


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
	var at := target.global_position + Vector3(cos(angle) * distance, 20.0, sin(angle) * distance)
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


## Server: an admin asked for a drone; it comes for them.
func _on_admin_spawn(p: Dictionary) -> void:
	if p.get("kind") == "drone" and multiplayer.is_server() and p.get("player") is Node3D:
		server_spawn(p["player"])
