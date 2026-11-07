class_name PlayerIntent
extends Node
## What the player wants to do this tick. Keyboard input, tests, bots and the network all
## write here; the controller only ever reads it.
##
## Over the network the owning client sends its intent to the server: continuous state
## (move, aim, held buttons) every tick, unreliably, since the next packet supersedes it;
## one-shot actions (jump, interact, reload, place charge) reliably, so none are lost. The
## client owns its aim and sends it absolute, so a dropped packet can't skew it.

## x = strafe right, y = forward. Length 0..1.
var move: Vector2 = Vector2.ZERO
## Accumulated look input in radians since the controller last consumed it (local play).
var look_delta: Vector2 = Vector2.ZERO
## Absolute aim from a remote client: body yaw and head pitch in radians.
var look_yaw: float = 0.0
var look_pitch: float = 0.0
## True once a remote client has sent its aim; the controller then uses it as-is.
var remote_look: bool = false
var sprint: bool = false
var crouch: bool = false
## One-shot: set when jump is pressed, cleared by the controller after it acts on it.
var jump: bool = false
## One-shot: use whatever is in front of the player (enter a car, later loot and doors).
var interact: bool = false
## Held while the trigger is down; whatever weapon the player carries reads it.
var fire: bool = false
## Held while aiming down sights: slower movement, no sprint, tighter spread.
var aim: bool = false
## One-shot: reload the carried weapon.
var reload: bool = false
## One-shot: place a demolition charge where the player aims.
var throw: bool = false

const ONE_SHOTS := [&"jump", &"interact", &"reload", &"throw"]


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


## Client -> server, every tick.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func submit(new_move: Vector2, yaw: float, pitch: float, new_sprint: bool, new_crouch: bool, new_fire: bool, new_aim: bool) -> void:
	if not _from_owner():
		return
	move = new_move.limit_length(1.0)
	look_yaw = yaw
	look_pitch = pitch
	remote_look = true
	sprint = new_sprint
	crouch = new_crouch
	fire = new_fire
	aim = new_aim


## Client -> server, once per press.
@rpc("any_peer", "call_remote", "reliable")
func submit_action(action: StringName) -> void:
	if not _from_owner() or not action in ONE_SHOTS:
		return
	set(action, true)


## Only the peer this player belongs to may steer it.
func _from_owner() -> bool:
	if not multiplayer.is_server():
		return false
	var owner_peer: int = get_parent().get_meta(&"peer_id", 0)
	var sender := multiplayer.get_remote_sender_id()
	if sender != owner_peer:
		Log.warn(&"net", "peer %d tried to steer player %d; ignored" % [sender, owner_peer])
		return false
	return true
