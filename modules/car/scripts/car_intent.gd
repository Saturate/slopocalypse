class_name CarIntent
extends Node
## What the people in the car want this tick. Keyboard and tests write here directly; a
## driver or passenger on a remote client sends it to the server through `submit` and
## `submit_exit`.

## -1 full reverse .. 1 full throttle.
var throttle: float = 0.0
## -1 full left .. 1 full right.
var steer: float = 0.0
var brake: bool = false
## One-shot: driver wants out.
var exit: bool = false
## One-shot: passenger wants out.
var passenger_exit: bool = false


func consume_exit() -> bool:
	var out := exit
	exit = false
	return out


func consume_passenger_exit() -> bool:
	var out := passenger_exit
	passenger_exit = false
	return out


## Client -> server, every physics tick while driving.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func submit(new_throttle: float, new_steer: float, new_brake: bool) -> void:
	if not _from_driver():
		return
	throttle = clampf(new_throttle, -1.0, 1.0)
	steer = clampf(new_steer, -1.0, 1.0)
	brake = new_brake


## Client -> server, once per press, from whichever seat the sender is in.
@rpc("any_peer", "call_remote", "reliable")
func submit_exit() -> void:
	if multiplayer.is_server() and _sender_sits_in(&"passenger"):
		passenger_exit = true
	elif _from_driver():
		exit = true


func _sender_sits_in(seat: StringName) -> bool:
	var who: Variant = get_parent().get(seat)
	return who is Node and multiplayer.get_remote_sender_id() == int((who as Node).get_meta(&"peer_id", 0))


## Only the peer whose player sits in the driver seat may steer this car.
func _from_driver() -> bool:
	if not multiplayer.is_server():
		return false
	if not _sender_sits_in(&"driver"):
		Log.warn(&"net", "peer %d tried to drive %s; ignored" % [multiplayer.get_remote_sender_id(), get_parent().name])
		return false
	return true


func clear() -> void:
	throttle = 0.0
	steer = 0.0
	brake = false
	exit = false
	passenger_exit = false
