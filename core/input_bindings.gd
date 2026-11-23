class_name InputBindings
extends RefCounted
## Registers input actions from module data at runtime, so project.godot never lists a
## module's keys and deleting a module leaves no input map behind.


## Each module action's own keys, kept even when the player has chosen another, so
## settings can put them back.
static var defaults: Dictionary[String, Array] = {}


## bindings: {"action_name": ["W", "Up"], ...} using Godot key names. An action that already
## exists (the player rebound it in settings) keeps its keys.
static func register(bindings: Dictionary, category: StringName) -> void:
	for action: String in bindings:
		defaults[action] = bindings[action]
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		restore(action, category)


## Puts the module's own keys back on `action`.
static func restore(action: String, category: StringName = &"input") -> void:
	if not defaults.has(action):
		return
	InputMap.action_erase_events(action)
	for key_name: String in defaults[action]:
		var keycode := OS.find_keycode_from_string(key_name)
		if keycode == KEY_NONE:
			Log.error(category, "unknown key '%s' for action '%s'" % [key_name, action])
			continue
		var ev := InputEventKey.new()
		ev.physical_keycode = keycode
		InputMap.action_add_event(action, ev)
