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
## Client: seats the server named when this client joined, kept until the car and the player
## in it have both appeared here. Each is {car, seat, player}, the nodes as paths.
var _pending_seats: Array[Dictionary] = []

## Kept loaded: Godot's resource cache lets go of a scene once nothing holds it, and loading
## a generated scene again from text costs tens of milliseconds per spawn.
var _packed_scene: PackedScene


func _scene() -> PackedScene:
	if _packed_scene == null:
		_packed_scene = load(SCENE)
	return _packed_scene


func cars() -> Array[CarController]:
	return _cars


func _physics_process(_delta: float) -> void:
	var prof := Prof.start()
	_physics_tick(_delta)
	Prof.stop(&"car/module:physics", prof)


func _physics_tick(_delta: float) -> void:
	if not _pending_seats.is_empty():
		_apply_pending_seats()
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
	add_to_group(&"cars_api")
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
	EventBus.subscribe(&"player.teleporting", _on_teleporting)
	EventBus.subscribe(&"admin.spawn", _on_admin_spawn)
	Net.peer_leaving.connect(_on_peer_leaving)
	Net.peer_joined.connect(_on_peer_joined)


func _exit_tree() -> void:
	Net.peer_leaving.disconnect(_on_peer_leaving)
	Net.peer_joined.disconnect(_on_peer_joined)
	EventBus.unsubscribe(&"world.ready", _on_world_ready)
	EventBus.unsubscribe(&"player.interact", _on_player_interact)
	EventBus.unsubscribe(&"car.entered", _on_car_entered)
	EventBus.unsubscribe(&"car.exited", _on_car_exited)
	EventBus.unsubscribe(&"player.spawned", _on_player_spawned)
	EventBus.unsubscribe(&"player.teleporting", _on_teleporting)
	EventBus.unsubscribe(&"admin.spawn", _on_admin_spawn)


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
	var car: CarController = _scene().instantiate()
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
	var who := payload.get("player") as Node3D
	if car == null or who == null:
		return
	car.show_seat(payload.get("seat", CarController.DRIVER), who)
	if not _is_local(who):
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
	if car == null:
		return
	var seat: StringName = payload.get("seat", CarController.DRIVER)
	car.show_seat(seat, null)
	_forget_pending_seat(car, seat)
	# Only when it is this instance's own player getting out: the other seat may still be
	# ours.
	if who == null or not _is_local(who):
		return
	var input := car.get_node_or_null("Input")
	if input != null:
		# Renamed first so getting straight back in names its new input "Input" again.
		input.name = "InputLeaving"
		input.queue_free()


## Where `player` would stand if they got out now (beside their door), or null when they are
## in no car. Saves use it, so a driver saved mid-drive comes back beside the car instead of
## where they got in, and nobody is moved to find out (#406).
func exit_spot_of(player: Node3D) -> Variant:
	for car in _cars:
		var seat := car.seat_of(player)
		if seat != &"":
			return car.exit_position(seat)
	return null


## Every taken seat as {car, seat, player}, the nodes as paths: what a late joiner needs.
func occupied_seats() -> Array[Dictionary]:
	var seats: Array[Dictionary] = []
	for car in _cars:
		for seat: StringName in [CarController.DRIVER, CarController.PASSENGER]:
			var who := car.driver if seat == CarController.DRIVER else car.passenger
			if who != null:
				seats.append({"car": car.get_path(), "seat": seat, "player": who.get_path()})
	return seats


## Server: `car.entered` only reached whoever was connected at the time, so someone who
## joins later is told who already sits in which car (#433).
func _on_peer_joined(peer: int) -> void:
	if not multiplayer.is_server() or not multiplayer.get_peers().has(peer):
		return
	for seat in occupied_seats():
		_catch_up.rpc_id(peer, seat["car"], seat["seat"], seat["player"])


@rpc("authority", "call_remote", "reliable")
func _catch_up(car: NodePath, seat: StringName, player: NodePath) -> void:
	catch_up_seat(car, seat, player)


## Late joiner: someone was already in a car. Replayed as the `car.entered` this client
## missed, so every module reacts as it does to someone getting in; held back until both
## nodes are here, because the spawners may deliver them after this.
func catch_up_seat(car: NodePath, seat: StringName, player: NodePath) -> void:
	_pending_seats.append({"car": car, "seat": seat, "player": player})
	_apply_pending_seats()


func _apply_pending_seats() -> void:
	var waiting: Array[Dictionary] = []
	for pending in _pending_seats:
		var car := get_node_or_null(pending["car"] as NodePath) as CarController
		var who := get_node_or_null(pending["player"] as NodePath)
		if car == null or who == null:
			waiting.append(pending)
		else:
			EventBus.publish(&"car.entered", {"player": who, "car": car, "seat": pending["seat"]})
	_pending_seats = waiting


## They got out before their player appeared here: nothing left to catch up on.
func _forget_pending_seat(car: CarController, seat: StringName) -> void:
	var path := car.get_path()
	_pending_seats = _pending_seats.filter(func(p: Dictionary) -> bool: return p["car"] != path or p["seat"] != seat)


## Server: someone leaving the server gets out of their car, so the seat is free.
func _on_peer_leaving(peer: int) -> void:
	if not multiplayer.is_server():
		return
	for car in _cars:
		for who: Node3D in [car.driver, car.passenger]:
			if who != null and int(who.get_meta(&"peer_id", 0)) == peer:
				car.exit_car(who)


## Server: someone being moved (back to the spawn, an admin teleport) gets out of their
## car first.
func _on_teleporting(p: Dictionary) -> void:
	var who := p.get("player") as Node3D
	for car in _cars:
		if car.seat_of(who) != &"":
			car.exit_car(who)


func _on_player_spawned(p: Dictionary) -> void:
	var behaviour := _bot_behaviour()
	if not p.get("local", false) or (behaviour != CarBot.BEHAVIOUR and behaviour != CarBot.SIT):
		return
	_bot = CarBot.new()
	_bot.name = "Bot"
	_bot.sit = behaviour == CarBot.SIT
	_bot.player = p["player"]
	add_child(_bot)


## True for the player controlled from this instance (solo or that client).
func _is_local(who: Node) -> bool:
	return Net.has_local_player() and int(who.get_meta(&"peer_id", 0)) == Net.local_peer_id()


## Session args, not only the command line: a menu choice adds `--bot=` too (the Benchmark).
func _bot_behaviour() -> String:
	for arg in Net.session_args():
		if arg.begins_with("--bot="):
			return arg.trim_prefix("--bot=")
	return ""


## Server: an admin asked for a car in front of them, nose pointing the way they face.
func _on_admin_spawn(p: Dictionary) -> void:
	if p.get("kind") != "car" or not multiplayer.is_server():
		return
	var forward: Vector3 = p.get("forward", Vector3.FORWARD)
	# Cars drive along their +Z.
	var basis := Basis.looking_at(-forward)
	var at: Vector3 = p["position"]
	_spawner.spawn({"index": _cars.size(), "transform": Transform3D(basis, at + Vector3.UP * LIFT_HEIGHT)})
