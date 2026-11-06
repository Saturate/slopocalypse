class_name CarIntent
extends Node
## What the driver wants this tick. Keyboard and tests write here directly; a driver on a
## remote client sends it to the server through `submit`.

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


## Client -> server, every physics tick while driving.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func submit(new_throttle: float, new_steer: float, new_brake: bool) -> void:
	if not _from_driver():
		return
	throttle = clampf(new_throttle, -1.0, 1.0)
	steer = clampf(new_steer, -1.0, 1.0)
	brake = new_brake


## Client -> server, once per press.
@rpc("any_peer", "call_remote", "reliable")
func submit_exit() -> void:
	if _from_driver():
		exit = true


## Only the peer whose player sits in the driver seat may steer this car.
func _from_driver() -> bool:
	if not multiplayer.is_server():
		return false
	var driver: Variant = get_parent().get(&"driver")
	var sender := multiplayer.get_remote_sender_id()
	if not driver is Node or sender != int((driver as Node).get_meta(&"peer_id", 0)):
		Log.warn(&"net", "peer %d tried to drive %s; ignored" % [sender, get_parent().name])
		return false
	return true


func clear() -> void:
	throttle = 0.0
	steer = 0.0
	brake = false
	exit = false
