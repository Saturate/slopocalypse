class_name CarInput
extends Node
## Client-only: keyboard to CarIntent while the local player sits in the car. The driver
## steers; either seat can get out. On a remote client the intent goes to the server, which
## simulates the car.

var intent: CarIntent
## The seat the local player is in (CarController.DRIVER or PASSENGER).
var seat: StringName = &"driver"
# Enter and exit share a key; ignore it until it has been released once, or the press
# that got us in would throw us straight back out.
var _exit_armed := false
var _remote := false


func _ready() -> void:
	_remote = not multiplayer.is_server()


func _physics_process(_delta: float) -> void:
	var driving := seat == &"driver"
	if driving:
		intent.throttle = Input.get_axis(&"car_reverse", &"car_throttle")
		intent.steer = Input.get_axis(&"car_left", &"car_right")
		intent.brake = Input.is_action_pressed(&"car_brake")
	if not Input.is_action_pressed(&"car_exit"):
		_exit_armed = true
	elif _exit_armed and Input.is_action_just_pressed(&"car_exit"):
		if driving:
			intent.exit = true
		else:
			intent.passenger_exit = true
		if _remote:
			intent.submit_exit.rpc_id(1)
	if _remote and driving:
		intent.submit.rpc_id(1, intent.throttle, intent.steer, intent.brake)
