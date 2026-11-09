class_name PlayerBot
extends Node
## Drives a player without a keyboard, through the same intent path a human uses: on a
## remote client it sends the intent to the server over the network. Used by the network
## smoke test (`--bot=walk`) and later by soak runs.
##
## "walk": walks forward turning slowly, firing short bursts.

## The behaviours this bot knows; other modules may handle other `--bot=` names.
const BEHAVIOURS: Array[String] = ["walk"]

var player: PlayerController
var behaviour := "walk"

var _ticks := 0
var _yaw := 0.0


func _ready() -> void:
	_yaw = player.rotation.y


func _physics_process(_delta: float) -> void:
	var prof := Prof.start()
	_physics_tick(_delta)
	Prof.stop(&"player/player_bot:physics", prof)


func _physics_tick(_delta: float) -> void:
	_ticks += 1
	var intent := player.intent()
	intent.move = Vector2(0.0, 1.0)
	_yaw += 0.004
	intent.fire = (_ticks % 90) < 10
	if multiplayer.is_server():
		player.rotation.y = _yaw
	else:
		intent.submit.rpc_id(1, intent.move, _yaw, 0.0, false, false, intent.fire, false)
