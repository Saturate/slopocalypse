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


func _ready() -> void:
	var data: Variant = Data.load_json(CONFIG)
	if not data is Dictionary or not Data.require(CONFIG, data, {"spawn_distance": TYPE_FLOAT, "respawn_seconds": TYPE_FLOAT, "max_drones": TYPE_FLOAT}):
		return
	config = data
	EventBus.subscribe(&"player.spawned", _on_player_spawned)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"player.spawned", _on_player_spawned)


func drones() -> Array[StalkerDrone]:
	return _drones


func _on_player_spawned(p: Dictionary) -> void:
	_players.append(p["player"])
	if _drones.is_empty():
		_respawn_in = 1.0


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or config.is_empty():
		return
	_players = _players.filter(func(n: Node3D) -> bool: return is_instance_valid(n))
	if _respawn_in >= 0.0:
		_respawn_in -= delta
		if _respawn_in < 0.0 and _drones.size() < int(config["max_drones"]) and not _players.is_empty():
			server_spawn(_players[_rng.randi() % _players.size()])


## Server only: a new drone appears high up at spawn distance from `target` and hunts it.
func server_spawn(target: Node3D) -> StalkerDrone:
	var drone: StalkerDrone = (load(SCENE) as PackedScene).instantiate()
	drone.target = target
	add_child(drone)
	var angle := _rng.randf() * TAU
	var distance: float = config["spawn_distance"]
	drone.global_position = target.global_position + Vector3(cos(angle) * distance, 20.0, sin(angle) * distance)
	drone.destroyed.connect(_on_drone_destroyed.bind(drone))
	_drones.append(drone)
	return drone


func _on_drone_destroyed(drone: StalkerDrone) -> void:
	_drones.erase(drone)
	_respawn_in = config["respawn_seconds"]
