extends Node
## Places a car near the spawn, lets a player in when they interact next to it, and hands
## the keyboard and camera to the car while they drive.

const SCENE := "res://modules/car/scenes/box_car.tscn"
## Beside the spawn pad, on flat ground, nose pointing away from the player.
const SPAWN_OFFSET := Vector3(5.0, 1.0, -3.0)

var _cars: Array[CarController] = []
var _spawn := Vector3.ZERO
var _kill_y := -INF


func _physics_process(_delta: float) -> void:
	# Safety net: a car that falls out of the world comes back upright beside the spawn.
	for car in _cars:
		if car.global_position.y < _kill_y:
			Log.warn(&"car", "fell out of the world at %s, respawning" % car.global_position)
			car.global_transform = Transform3D(Basis.IDENTITY, _spawn + SPAWN_OFFSET)
			car.linear_velocity = Vector3.ZERO
			car.angular_velocity = Vector3.ZERO


func _ready() -> void:
	EventBus.subscribe(&"world.ready", _on_world_ready)
	EventBus.subscribe(&"player.interact", _on_player_interact)
	EventBus.subscribe(&"car.entered", _on_car_entered)
	EventBus.subscribe(&"car.exited", _on_car_exited)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"world.ready", _on_world_ready)
	EventBus.unsubscribe(&"player.interact", _on_player_interact)
	EventBus.unsubscribe(&"car.entered", _on_car_entered)
	EventBus.unsubscribe(&"car.exited", _on_car_exited)


func _on_world_ready(payload: Dictionary) -> void:
	_spawn = payload["spawn"]
	_kill_y = payload.get("kill_y", -INF)
	var car: CarController = (load(SCENE) as PackedScene).instantiate()
	add_child(car)
	car.global_position = _spawn + SPAWN_OFFSET
	_cars.append(car)
	if DisplayServer.get_name() != "headless":
		InputBindings.register(car.config.get("bindings", {}), &"car")


func _on_player_interact(payload: Dictionary) -> void:
	var who: Node3D = payload["player"]
	for car in _cars:
		if car.can_enter(who):
			car.enter(who)
			return


func _on_car_entered(payload: Dictionary) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var car: CarController = payload["car"]
	var input := CarInput.new()
	input.name = "Input"
	input.intent = car.intent()
	car.add_child(input)
	car.camera().current = true


func _on_car_exited(payload: Dictionary) -> void:
	var car: CarController = payload["car"]
	var input := car.get_node_or_null("Input")
	if input != null:
		input.queue_free()
