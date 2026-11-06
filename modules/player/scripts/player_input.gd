class_name PlayerInput
extends Node
## Client-only: turns keyboard and mouse into PlayerIntent. Never added on the server
## or in tests, where intent is set directly.

var intent: PlayerIntent
var sensitivity: float = 0.0025


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion: InputEventMouseMotion = event
		intent.look_delta += motion.relative * sensitivity
	elif event is InputEventKey and event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.is_pressed():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(_delta: float) -> void:
	intent.move = Input.get_vector(&"move_left", &"move_right", &"move_back", &"move_forward")
	intent.sprint = Input.is_action_pressed(&"sprint")
	intent.crouch = Input.is_action_pressed(&"crouch")
	if Input.is_action_just_pressed(&"jump"):
		intent.jump = true


## Registers the module's actions from data so project.godot never needs editing and
## deleting the module leaves no input map behind.
static func register_bindings(bindings: Dictionary) -> void:
	for action: String in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key_name: String in bindings[action]:
			var keycode := OS.find_keycode_from_string(key_name)
			if keycode == KEY_NONE:
				Log.error(&"player", "unknown key '%s' for action '%s'" % [key_name, action])
				continue
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			InputMap.action_add_event(action, ev)
