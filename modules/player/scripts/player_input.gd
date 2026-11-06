class_name PlayerInput
extends Node
## Client-only: turns keyboard and mouse into PlayerIntent. Never added on the server or in
## tests, where intent is set directly.
##
## On a remote client this also owns the aim: it turns the body and head itself every frame
## (so looking around never waits on the network) and sends the intent to the server.

var intent: PlayerIntent
var player: PlayerController
var sensitivity: float = 0.0025

var _yaw := 0.0
var _pitch := 0.0
var _remote := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_remote = not multiplayer.is_server()
	_yaw = player.rotation.y
	# Runs after the synchronizer has written the server's copy of our rotation.
	process_priority = 100


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion: InputEventMouseMotion = event
		intent.look_delta += motion.relative * sensitivity
	elif event is InputEventKey and event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.is_pressed():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	if not _remote:
		return
	# Our own aim, applied locally and immediately; recoil arrives as look_delta too.
	var look := intent.consume_look()
	_yaw -= look.x
	_pitch = clampf(_pitch - look.y, -PlayerController.PITCH_LIMIT, PlayerController.PITCH_LIMIT)
	player.rotation.y = _yaw
	(player.get_node("Head") as Node3D).rotation.x = _pitch


func _physics_process(_delta: float) -> void:
	intent.move = Input.get_vector(&"move_left", &"move_right", &"move_back", &"move_forward")
	intent.sprint = Input.is_action_pressed(&"sprint")
	intent.crouch = Input.is_action_pressed(&"crouch")
	# The click that captures the mouse should not also fire.
	intent.fire = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	for action: StringName in PlayerIntent.ONE_SHOTS:
		var input_action := &"charge" if action == &"throw" else action
		if Input.is_action_just_pressed(input_action):
			if _remote:
				intent.submit_action.rpc_id(1, action)
			else:
				intent.set(action, true)
	if _remote:
		intent.submit.rpc_id(1, intent.move, _yaw, _pitch, intent.sprint, intent.crouch, intent.fire)
