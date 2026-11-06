class_name InputBindings
extends RefCounted
## Registers input actions from module data at runtime, so project.godot never lists a
## module's keys and deleting a module leaves no input map behind.


## bindings: {"action_name": ["W", "Up"], ...} using Godot key names.
static func register(bindings: Dictionary, category: StringName) -> void:
	for action: String in bindings:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key_name: String in bindings[action]:
			var keycode := OS.find_keycode_from_string(key_name)
			if keycode == KEY_NONE:
				Log.error(category, "unknown key '%s' for action '%s'" % [key_name, action])
				continue
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			InputMap.action_add_event(action, ev)
