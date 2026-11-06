class_name PlayerIntent
extends Node
## What the player wants to do this tick. Keyboard input, tests, bots and (later) the
## network all write here; the controller only ever reads it.

## x = strafe right, y = forward. Length 0..1.
var move: Vector2 = Vector2.ZERO
## Accumulated look input in radians since the controller last consumed it.
var look_delta: Vector2 = Vector2.ZERO
var sprint: bool = false
var crouch: bool = false
## One-shot: set when jump is pressed, cleared by the controller after it acts on it.
var jump: bool = false
## One-shot: use whatever is in front of the player (enter a car, later loot and doors).
var interact: bool = false
## Held while the trigger is down; whatever weapon the player carries reads it.
var fire: bool = false
## One-shot: reload the carried weapon.
var reload: bool = false
## One-shot: place a demolition charge where the player aims.
var throw: bool = false


func consume_look() -> Vector2:
	var out := look_delta
	look_delta = Vector2.ZERO
	return out


func consume_jump() -> bool:
	var out := jump
	jump = false
	return out


func consume_interact() -> bool:
	var out := interact
	interact = false
	return out


func consume_reload() -> bool:
	var out := reload
	reload = false
	return out


func consume_throw() -> bool:
	var out := throw
	throw = false
	return out
