extends Node
## Loads the world scene and announces it once every module has been added.

const SCENE := "res://modules/world/scenes/world.tscn"


func _ready() -> void:
	var scene: PackedScene = load(SCENE)
	var world := scene.instantiate()
	add_child(world)
	var spawn: Marker3D = world.get_node("SpawnPoint")
	# Deferred so modules loaded after this one have subscribed before it fires.
	EventBus.publish.call_deferred(&"world.ready", {"spawn": spawn.global_position})
