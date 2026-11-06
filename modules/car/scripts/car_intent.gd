class_name CarIntent
extends Node
## What the driver wants this tick. Keyboard, tests and (later) the network write here.

## -1 full reverse .. 1 full throttle.
var throttle: float = 0.0
## -1 full left .. 1 full right.
var steer: float = 0.0
var brake: bool = false
## One-shot: driver wants out.
var exit: bool = false


func consume_exit() -> bool:
	var out := exit
	exit = false
	return out


func clear() -> void:
	throttle = 0.0
	steer = 0.0
	brake = false
	exit = false
