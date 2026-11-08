extends Node
## Places a car near the spawn, lets a player in when they interact next to it, and hands
## the keyboard and camera to the car while they drive.

const SCENE := "res://modules/car/scenes/box_car.tscn"
## Beside the spawn, when the world names no car spot.
const SPAWN_OFFSET := Vector3(5.0, 1.0, -3.0)
## Same height above the ground a car is spawned at.
const LIFT_HEIGHT := 1.0

var _cars: Array[CarController] = []
var _spawn := Vector3.ZERO
## Where a car starts and goes back to when it is lost.
var _home := Transform3D(Basis.IDENTITY, SPAWN_OFFSET)
var _kill_y := -INF
var _rescue_depth := INF
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
		# Safety net: a car that slips under the terrain comes back upright on top where it
		# was, frozen until its ground has collision; one lost entirely goes to the spawn.
		elif car.global_position.y < _kill_y:
			Log.warn(&"car", "fell out of the world at %s, respawning" % car.global_position)
			_place(car)
		elif car.global_position.y < _ground_height(car.global_position) - _rescue_depth:
			Log.warn(&"car", "fell through the ground at %s, putting it back on top" % car.global_position)
			_lift(car)


## Puts a car at its spawn, frozen until there is ground under it. Voxel collision is built
## per 16 m block and can arrive after the spawn point's own block, so a car placed beside
## the spawn could otherwise drop through before its ground exists.
func _place(car: CarController) -> void:
	car.global_transform = _home
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.freeze = true


## Puts a car back on top of the ground where it is, upright, keeping its heading.
func _lift(car: CarController) -> void:
	var at := car.global_position
	var heading := car.global_transform.basis.z
	heading.y = 0.0
	var basis := Basis.looking_at(-heading.normalized()) if heading.length() > 0.01 else Basis.IDENTITY
	car.global_transform = Transform3D(basis, Vector3(at.x, _ground_height(at) + LIFT_HEIGHT, at.z))
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.freeze = true


## The untouched ground height from the world module (answers where no terrain is loaded).
func _ground_height(at: Vector3) -> float:
	var ground := get_tree().get_first_node_in_group(&"ground")
	return float(ground.call(&"ground_height", at.x, at.z)) if ground != null else _spawn.y


func _release_when_grounded(car: CarController) -> void:
	var from := car.global_position + Vector3.UP * 2.0
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 12.0, PhysicsLayers.SOLID, [car.get_rid()])
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
	EventBus.subscribe(&"player.back_to_spawn", _on_back_to_spawn)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"world.ready", _on_world_ready)
	EventBus.unsubscribe(&"player.interact", _on_player_interact)
	EventBus.unsubscribe(&"car.entered", _on_car_entered)
	EventBus.unsubscribe(&"car.exited", _on_car_exited)
	EventBus.unsubscribe(&"player.spawned", _on_player_spawned)
	EventBus.unsubscribe(&"player.back_to_spawn", _on_back_to_spawn)


func _on_world_ready(payload: Dictionary) -> void:
	_spawn = payload["spawn"]
	_home = payload.get("car", Transform3D(Basis.IDENTITY, _spawn + SPAWN_OFFSET))
	_kill_y = payload.get("kill_y", -INF)
	_rescue_depth = payload.get("rescue_depth", INF)
	if DisplayServer.get_name() != "headless":
		InputBindings.register(CarController.bindings(), &"car")
	if multiplayer.is_server():
		_spawner.spawn({"index": _cars.size(), "transform": _home})


## Runs on the server and, through the spawner, on every client.
func _spawn_car(data: Variant) -> Node:
	var info: Dictionary = data
	var car: CarController = (load(SCENE) as PackedScene).instantiate()
	car.name = "Car%d" % int(info["index"])
	car.transform = info["transform"]
	car.add_to_group(&"vehicles")
	car.set_meta(&"spawn_position", (info["transform"] as Transform3D).origin)
	# Frozen until the server finds ground under it. Client copies stay frozen for good:
	# they only show the transform the server syncs.
	car.freeze = true
	_cars.append(car)
	return car


func _on_player_interact(payload: Dictionary) -> void:
	# One press does one thing: something else (picking up loot) may have claimed it.
	if payload.get("handled", false):
		return
	var who: Node3D = payload["player"]
	for car in _cars:
		if car.can_enter(who):
			payload["handled"] = true
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
	input.seat = payload.get("seat", CarController.DRIVER)
	car.add_child(input)
	car.camera().current = true


func _on_car_exited(payload: Dictionary) -> void:
	var car := payload.get("car") as CarController
	var who := payload.get("player") as Node
	# Only when it is this instance's own player getting out: the other seat may still be
	# ours.
	if car == null or who == null or not _is_local(who):
		return
	var input := car.get_node_or_null("Input")
	if input != null:
		# Renamed first so getting straight back in names its new input "Input" again.
		input.name = "InputLeaving"
		input.queue_free()


## Server: someone going back to the spawn gets out of their car first.
func _on_back_to_spawn(p: Dictionary) -> void:
	var who := p.get("player") as Node3D
	for car in _cars:
		if car.seat_of(who) != &"":
			car.exit_car(who)


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
