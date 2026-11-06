extends Node
## Spawns the local player when the world is ready, and parks or restores it when another
## module (the car) takes over. Until the dedicated server exists (#9) this is the single
## local player; spawning moves to the server then.

const SCENE := "res://modules/player/scenes/player.tscn"

var _player: PlayerController


func _ready() -> void:
	EventBus.subscribe(&"world.ready", _on_world_ready)
	EventBus.subscribe(&"car.entered", _on_car_entered)
	EventBus.subscribe(&"car.exited", _on_car_exited)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"world.ready", _on_world_ready)
	EventBus.unsubscribe(&"car.entered", _on_car_entered)
	EventBus.unsubscribe(&"car.exited", _on_car_exited)


func _on_world_ready(payload: Dictionary) -> void:
	var scene: PackedScene = load(SCENE)
	_player = scene.instantiate()
	_player.name = "LocalPlayer"
	add_child(_player)
	_player.global_position = payload["spawn"]
	if DisplayServer.get_name() == "headless":
		return
	InputBindings.register(_player.config.get("bindings", {}), &"player")
	var input := PlayerInput.new()
	input.name = "Input"
	input.intent = _player.intent()
	input.sensitivity = _player.config["mouse_sensitivity"]
	_player.add_child(input)
	_camera().current = true
	# The local player's own body would block the first-person camera.
	(_player.get_node("BodyMesh") as MeshInstance3D).visible = false


func _on_car_entered(payload: Dictionary) -> void:
	if payload.get("player") != _player:
		return
	# Parked, not freed: the same player comes back on exit.
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	_player.visible = false
	(_player.get_node("Shape") as CollisionShape3D).set_deferred(&"disabled", true)


func _on_car_exited(payload: Dictionary) -> void:
	if payload.get("player") != _player:
		return
	_player.global_position = payload["position"]
	_player.velocity = Vector3.ZERO
	_player.process_mode = Node.PROCESS_MODE_INHERIT
	_player.visible = true
	(_player.get_node("Shape") as CollisionShape3D).set_deferred(&"disabled", false)
	if DisplayServer.get_name() != "headless":
		_camera().current = true


func _camera() -> Camera3D:
	return _player.get_node("Head/Camera")
