class_name CarBot
extends Node
## Test driver (`--bot=drive`): walks this instance's player to the nearest car, gets in,
## drives for a few seconds and gets out again, through the same intent path a human uses.
## `--bot=sit` gets in and stays in the driver's seat, for tests that need a car occupied.
## Lives under the car module, not the player, because a parked player stops processing.

const BEHAVIOUR := "drive"
const SIT := "sit"
const SEATED_LOG := "bot seated"
## Let the player land and the car settle before walking over.
const WAIT_TICKS := 90
## Drives for DRIVE_TICKS, and on until the car, as this instance sees it, is DRIVE_DISTANCE
## from where the bot got in (the net smoke checks for 5 m), for at most DRIVE_TICKS_MAX: the
## ticks are this client's, and the car may not move at once (still frozen until it has
## ground, the throttle reaching a loaded server late), so time alone does not say it went
## anywhere (#581).
const DRIVE_TICKS := 240
const DRIVE_DISTANCE := 8.0
const DRIVE_TICKS_MAX := 600
## Inside the car's enter_distance (car.json, 3.5) and past where its body stops a walker
## coming at it end on (about 2.6 m from its middle).
const ENTER_RANGE := 3.0
const INTERACT_EVERY := 30
const DRIVE_STEER := 0.15

enum State { WALK, DRIVE, DONE }

var player: PlayerController
## Stay seated with the brake on instead of driving off and getting out.
var sit := false

var _state := State.WALK
var _car: CarController
var _ticks := 0
var _drive_from := Vector3.ZERO


## Called by the car module when this bot's player is in a car.
func entered(car: CarController) -> void:
	_car = car
	_state = State.DRIVE
	_ticks = 0
	_drive_from = car.global_position
	if sit:
		# tools/lib/net.ts lateJoinSmoke waits for this line before a second client joins.
		Log.info(&"car", SEATED_LOG)


func _physics_process(_delta: float) -> void:
	var prof := Prof.start()
	_physics_tick(_delta)
	Prof.stop(&"car/car_bot:physics", prof)


func _physics_tick(_delta: float) -> void:
	if not is_instance_valid(player):
		return
	_ticks += 1
	match _state:
		State.WALK:
			_walk_to_car()
		State.DRIVE:
			_drive()


func _walk_to_car() -> void:
	if _ticks < WAIT_TICKS:
		return
	var car := _nearest_car()
	if car == null:
		return
	var to := car.global_position - player.global_position
	to.y = 0.0
	var near := to.length() < ENTER_RANGE
	# A Godot node faces -Z, so this yaw points the player along `to`.
	var yaw := atan2(-to.x, -to.z)
	_send_move(Vector2.ZERO if near else Vector2(0.0, 1.0), yaw)
	if near and _ticks % INTERACT_EVERY == 0:
		_send_interact()


func _drive() -> void:
	var intent := _car.intent()
	if sit:
		_send_car(intent, 0.0, 0.0, true)
		return
	if _ticks < DRIVE_TICKS or (_ticks < DRIVE_TICKS_MAX and _car.global_position.distance_to(_drive_from) < DRIVE_DISTANCE):
		_send_car(intent, 1.0, DRIVE_STEER, false)
		return
	_send_car(intent, 0.0, 0.0, true)
	if multiplayer.is_server():
		intent.exit = true
	else:
		intent.submit_exit.rpc_id(1)
	_state = State.DONE


func _nearest_car() -> CarController:
	var best: CarController = null
	for node in get_tree().get_nodes_in_group(&"vehicles"):
		var car := node as CarController
		if car != null and (best == null or car.global_position.distance_to(player.global_position) < best.global_position.distance_to(player.global_position)):
			best = car
	return best


func _send_move(move: Vector2, yaw: float) -> void:
	var intent := player.intent()
	if multiplayer.is_server():
		intent.move = move
		player.rotation.y = yaw
	else:
		intent.submit.rpc_id(1, move, yaw, 0.0, false, false, false, false)


func _send_interact() -> void:
	if multiplayer.is_server():
		player.intent().interact = true
	else:
		player.intent().submit_action.rpc_id(1, &"interact")


func _send_car(intent: CarIntent, throttle: float, steer: float, brake: bool) -> void:
	if multiplayer.is_server():
		intent.throttle = throttle
		intent.steer = steer
		intent.brake = brake
	else:
		intent.submit.rpc_id(1, throttle, steer, brake)
