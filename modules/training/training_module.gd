extends Node
## Places training dummies in front of the spawn once the world is ready.

const SCENE := "res://modules/training/scenes/dummy.tscn"
const CONFIG := "res://modules/training/data/training.json"


func _ready() -> void:
	EventBus.subscribe(&"world.ready", _on_world_ready)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"world.ready", _on_world_ready)


func _on_world_ready(payload: Dictionary) -> void:
	var data: Variant = Data.load_json(CONFIG)
	if not data is Dictionary or not Data.require(CONFIG, data, {"dummies": TYPE_ARRAY}):
		return
	var spawn: Vector3 = payload["spawn"]
	var scene: PackedScene = load(SCENE)
	# Terrain collision added this frame isn't in the physics space until the next step.
	await get_tree().physics_frame
	var space := get_viewport().world_3d.direct_space_state
	var index := 0
	for spot: Dictionary in data["dummies"]:
		var dummy: DummyTarget = scene.instantiate()
		dummy.name = "Dummy%d" % index
		add_child(dummy)
		dummy.global_position = _ground_at(space, spawn.x + float(spot["x"]), spawn.z + float(spot["z"]))
		index += 1


## Drops a ray onto whatever ground is there, so dummies stand on hills too.
func _ground_at(space: PhysicsDirectSpaceState3D, x: float, z: float) -> Vector3:
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 100.0, z), Vector3(x, -100.0, z)))
	return hit["position"] if not hit.is_empty() else Vector3(x, 0.0, z)
