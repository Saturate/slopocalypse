extends Node
## Loads the world scene and announces it once every module has been added. The
## announcement carries the spawn point and the height below which things count as fallen
## out of the world, so each module can rescue its own entities.

const SCENE := "res://modules/world/scenes/world.tscn"
const CONFIG := "res://modules/world/data/world.json"


func _ready() -> void:
	var data: Variant = Data.load_json(CONFIG)
	if not data is Dictionary or not Data.require(CONFIG, data, {"kill_y": TYPE_FLOAT}):
		return
	var scene: PackedScene = load(SCENE)
	var world := scene.instantiate()
	add_child(world)
	var spawn: Marker3D = world.get_node("SpawnPoint")
	# Deferred so modules loaded after this one have subscribed before it fires.
	EventBus.publish.call_deferred(&"world.ready", {"spawn": spawn.global_position, "kill_y": data["kill_y"]})
