extends Node
## Places a car near the spawn, lets a player in when they interact next to it, and hands
## the keyboard and camera to the car while they drive.

const SCENE := "res://modules/car/scenes/box_car.tscn"
## Beside the spawn pad, on flat ground, nose pointing away from the player.
const SPAWN_OFFSET := Vector3(5.0, 1.0, -3.0)

var _cars: Array[CarController] = []
var _spawn := Vector3.ZERO
var _kill_y := -INF
var _spawner := MultiplayerSpawner.new()
var _bot: CarBot


func cars() -> Array[CarController]:
	return _cars


func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server():
		return
	for car in _cars:
		if car.freeze:
			_release_when_grounded(car)
		# Safety net: a car that falls out of the world comes back upright beside the spawn.
		elif car.global_position.y < _kill_y:
			Log.warn(&"car", "fell out of the world at %s, respawning" % car.global_position)
			_place(car)


## Puts a car at its spawn, frozen until there is ground under it. Voxel collision is built
## per 16 m block and can arrive after the spawn point's own block, so a car placed beside
## the spawn could otherwise drop through before its ground exists.
func _place(car: CarController) -> void:
	car.global_transform = Transform3D(Basis.IDENTITY, _spawn + SPAWN_OFFSET)
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.freeze = true


func _release_when_grounded(car: CarController) -> void:
	var from := car.global_position + Vector3.UP * 2.0
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 12.0, 0xFFFFFFFF, [car.get_rid()])
	if not car.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		car.freeze = false


func _ready() -> void:
	# The server spawns cars; the spawner replicates them to clients.
	_spawner.name = "Spawner"
	_spawner.spawn_path = NodePath("..")
	_spawner.spawn_function = _spawn_car
	add_child(_spawner)
	EventBus.subscribe(&"world.ready", _on_world_ready)
	EventBus.subscribe(&"player.interact", _on_player_interact)
	EventBus.subscribe(&"car.entered", _on_car_entered)
	EventBus.subscribe(&"car.exited", _on_car_exited)
	EventBus.subscribe(&"player.spawned", _on_player_spawned)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"world.ready", _on_world_ready)
	EventBus.unsubscribe(&"player.interact", _on_player_interact)
	EventBus.unsubscribe(&"car.entered", _on_car_entered)
	EventBus.unsubscribe(&"car.exited", _on_car_exited)
	EventBus.unsubscribe(&"player.spawned", _on_player_spawned)


func _on_world_ready(payload: Dictionary) -> void:
	_spawn = payload["spawn"]
	_kill_y = payload.get("kill_y", -INF)
	if DisplayServer.get_name() != "headless":
		InputBindings.register(CarController.bindings(), &"car")
	if multiplayer.is_server():
		_spawner.spawn({"index": _cars.size(), "position": _spawn + SPAWN_OFFSET})


## Runs on the server and, through the spawner, on every client.
func _spawn_car(data: Variant) -> Node:
	var info: Dictionary = data
	var car: CarController = (load(SCENE) as PackedScene).instantiate()
	car.name = "Car%d" % int(info["index"])
	car.position = info["position"]
	car.add_to_group(&"vehicles")
	car.set_meta(&"spawn_position", info["position"])
	# Frozen until the server finds ground under it. Client copies stay frozen for good:
	# they only show the transform the server syncs.
	car.freeze = true
	_cars.append(car)
	return car


func _on_player_interact(payload: Dictionary) -> void:
	var who: Node3D = payload["player"]
	for car in _cars:
		if car.can_enter(who):
			car.enter(who)
			return


func _on_car_entered(payload: Dictionary) -> void:
	var car := payload.get("car") as CarController
	var who := payload.get("player") as Node
	if car == null or who == null or not _is_local(who):
		return
	if _bot != null:
		_bot.entered(car)
		return
	if DisplayServer.get_name() == "headless":
		return
	var input := CarInput.new()
	input.name = "Input"
	input.intent = car.intent()
	car.add_child(input)
	car.camera().current = true


func _on_car_exited(payload: Dictionary) -> void:
	var car := payload.get("car") as CarController
	if car == null:
		return
	var input := car.get_node_or_null("Input")
	if input != null:
		input.queue_free()


func _on_player_spawned(p: Dictionary) -> void:
	if not p.get("local", false) or _bot_behaviour() != CarBot.BEHAVIOUR:
		return
	_bot = CarBot.new()
	_bot.name = "Bot"
	_bot.player = p["player"]
	add_child(_bot)


## True for the player controlled from this instance (solo or that client).
func _is_local(who: Node) -> bool:
	return Net.has_local_player() and int(who.get_meta(&"peer_id", 0)) == Net.local_peer_id()


func _bot_behaviour() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bot="):
			return arg.trim_prefix("--bot=")
	return ""
