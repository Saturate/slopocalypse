class_name PlayerInput
extends Node
## Client-only: turns keyboard and mouse into PlayerIntent. Never added on the server or in
## tests, where intent is set directly.
##
## On a remote client this also owns the aim: it turns the body and head itself every frame
## (so looking around never waits on the network) and sends the intent to the server.

## One-shot actions sent by a menu button (the session overlay), not a key.
const FROM_MENU: Array[StringName] = [&"back_to_spawn"]

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
		# Zoomed in, the same mouse motion turns less, so aim speed feels the same on screen.
		var camera := player.get_node("Head/Camera") as Camera3D
		var zoom := camera.fov / float(player.config["fov"])
		intent.look_delta += motion.relative * sensitivity * zoom
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
	# A free mouse means a menu or panel is up (pause, modding): the player stands still
	# instead of walking off while the keys are used for it.
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		intent.move = Vector2.ZERO
		intent.sprint = false
		intent.crouch = false
		intent.lean = 0
		intent.fire = false
		intent.aim = false
		if _remote:
			intent.submit.rpc_id(1, intent.move, _yaw, _pitch, intent.sprint, intent.crouch, intent.fire, intent.aim, intent.lean)
		return
	intent.move = Input.get_vector(&"move_left", &"move_right", &"move_back", &"move_forward")
	intent.sprint = Input.is_action_pressed(&"sprint")
	intent.crouch = Input.is_action_pressed(&"crouch")
	intent.lean = int(Input.is_action_pressed(&"lean_right")) - int(Input.is_action_pressed(&"lean_left"))
	# The click that captures the mouse should not also fire.
	intent.fire = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	intent.aim = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	for action: StringName in PlayerIntent.ONE_SHOTS:
		# Menu-only actions have no key; asking Input about them logs an error every frame.
		if action in FROM_MENU:
			continue
		var input_action := &"charge" if action == &"throw" else action
		if Input.is_action_just_pressed(input_action):
			if _remote:
				intent.submit_action.rpc_id(1, action)
			else:
				intent.set(action, true)
	if _remote:
		intent.submit.rpc_id(1, intent.move, _yaw, _pitch, intent.sprint, intent.crouch, intent.fire, intent.aim, intent.lean)
