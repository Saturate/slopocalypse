extends Node
## The server places training dummies in front of the spawn once the world is ready; a
## MultiplayerSpawner replicates them to clients.

const SCENE := "res://modules/training/scenes/dummy.tscn"
const CONFIG := "res://modules/training/data/training.json"

var _spawner := MultiplayerSpawner.new()

## Kept loaded: Godot's resource cache lets go of a scene once nothing holds it, and loading
## a generated scene again from text costs tens of milliseconds per spawn.
var _packed_scene: PackedScene


func _scene() -> PackedScene:
	if _packed_scene == null:
		_packed_scene = load(SCENE)
	return _packed_scene


func _ready() -> void:
	_spawner.name = "Spawner"
	_spawner.spawn_path = NodePath("..")
	_spawner.spawn_function = _spawn_dummy
	add_child(_spawner)
	EventBus.subscribe(&"world.ready", _on_world_ready)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"world.ready", _on_world_ready)


func _on_world_ready(payload: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var data: Variant = Data.load_json(CONFIG)
	if not data is Dictionary or not Data.require(CONFIG, data, {"dummies": TYPE_ARRAY}):
		return
	var spawn: Vector3 = payload["spawn"]
	# Terrain collision added this frame isn't in the physics space until the next step.
	await get_tree().physics_frame
	# Viewport.world_3d is only the viewport's own override and is null for the root;
	# find_world_3d() returns the world the scene actually uses.
	var space := get_viewport().find_world_3d().direct_space_state
	var index := 0
	for spot: Dictionary in data["dummies"]:
		var at := _ground_at(space, spawn.x + float(spot["x"]), spawn.z + float(spot["z"]))
		_spawner.spawn({"index": index, "position": at})
		index += 1


## Runs on the server and, through the spawner, on every client.
func _spawn_dummy(data: Variant) -> Node:
	var info: Dictionary = data
	var dummy: DummyTarget = _scene().instantiate()
	dummy.name = "Dummy%d" % int(info["index"])
	dummy.position = info["position"]
	return dummy


## Drops a ray onto whatever ground is there, so dummies stand on hills too.
func _ground_at(space: PhysicsDirectSpaceState3D, x: float, z: float) -> Vector3:
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 100.0, z), Vector3(x, -100.0, z)))
	return hit["position"] if not hit.is_empty() else Vector3(x, 0.0, z)
