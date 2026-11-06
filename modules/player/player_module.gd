extends Node
## Spawns the local player when the world is ready. Until the dedicated server exists (#9)
## this is the single local player; spawning moves to the server then.

const SCENE := "res://modules/player/scenes/player.tscn"


func _ready() -> void:
	EventBus.subscribe(&"world.ready", _on_world_ready)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"world.ready", _on_world_ready)


func _on_world_ready(payload: Dictionary) -> void:
	var scene: PackedScene = load(SCENE)
	var player: PlayerController = scene.instantiate()
	player.name = "LocalPlayer"
	add_child(player)
	player.global_position = payload["spawn"]
	if DisplayServer.get_name() == "headless":
		return
	PlayerInput.register_bindings(player.config.get("bindings", {}))
	var input := PlayerInput.new()
	input.name = "Input"
	input.intent = player.intent()
	input.sensitivity = player.config["mouse_sensitivity"]
	player.add_child(input)
	var camera: Camera3D = player.get_node("Head/Camera")
	camera.current = true
	# The local player's own body would block the first-person camera.
	(player.get_node("BodyMesh") as MeshInstance3D).visible = false
