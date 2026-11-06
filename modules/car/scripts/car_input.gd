class_name CarInput
extends Node
## Client-only: keyboard to CarIntent while the local player drives.

var intent: CarIntent
# Enter and exit share a key; ignore it until it has been released once, or the press
# that got us in would throw us straight back out.
var _exit_armed := false


func _physics_process(_delta: float) -> void:
	intent.throttle = Input.get_axis(&"car_reverse", &"car_throttle")
	intent.steer = Input.get_axis(&"car_left", &"car_right")
	intent.brake = Input.is_action_pressed(&"car_brake")
	if not Input.is_action_pressed(&"car_exit"):
		_exit_armed = true
	elif _exit_armed and Input.is_action_just_pressed(&"car_exit"):
		intent.exit = true
