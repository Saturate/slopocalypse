class_name Settings
extends RefCounted
## The player's own settings, kept in user://settings.cfg: mouse sensitivity, field of view,
## volume, fullscreen, UI scale, blood, the compass strip, the co-op partner marker and key
## bindings. Gameplay code asks for the values (`mouse_scale()`, `fov_offset()`); boot applies
## the rest once at start.
##
## Static, like UiStack: one set per machine, no node needed. It still reaches autoloads by
## name: `save()` logs through Log, and `set_value()` and `reset()` announce real changes on
## the EventBus as `settings.changed` ({key, value}) for modules that act on a setting at once.

const PATH := "user://settings.cfg"

const MOUSE_MIN := 0.25
const MOUSE_MAX := 3.0
## Degrees added to the game's field of view.
const FOV_MIN := -15.0
const FOV_MAX := 30.0
const UI_MIN := 0.8
const UI_MAX := 1.4

const DEFAULTS := {
	"mouse_scale": 1.0,
	"fov_offset": 0.0,
	"volume": 1.0,
	"fullscreen": false,
	"ui_scale": 1.0,
	"blood": true,
	"compass": true,
	"coop_marker": true,
}

static var _values: Dictionary = DEFAULTS.duplicate()
## action -> physical keycode the player chose.
static var _keys: Dictionary[String, int] = {}
static var _path := PATH


static func load_from(path := PATH) -> void:
	_path = path
	_values = DEFAULTS.duplicate()
	_keys.clear()
	var file := ConfigFile.new()
	if file.load(path) != OK:
		return
	for key: String in DEFAULTS:
		_values[key] = file.get_value("game", key, DEFAULTS[key])
	_clamp()
	if file.has_section("keys"):
		for action: String in file.get_section_keys("keys"):
			_keys[action] = int(file.get_value("keys", action, KEY_NONE))


static func save() -> void:
	var file := ConfigFile.new()
	for key: String in _values:
		file.set_value("game", key, _values[key])
	for action: String in _keys:
		file.set_value("keys", action, _keys[action])
	var err := file.save(_path)
	if err != OK:
		Log.warn(&"settings", "could not save %s (%s)" % [_path, error_string(err)])


static func value(key: String) -> Variant:
	return _values.get(key, DEFAULTS.get(key))


## Sets `key` and tells modules that read a setting as they go (gore's blood) through
## `settings.changed` ({key, value}), only when the value really changes.
static func set_value(key: String, v: Variant) -> void:
	var before: Variant = value(key)
	_values[key] = v
	_clamp()
	_announce(key, before)


static func mouse_scale() -> float:
	return float(value("mouse_scale"))


static func fov_offset() -> float:
	return float(value("fov_offset"))


## Everything back to the game's defaults, keys included.
static func reset() -> void:
	var before := _values.duplicate()
	_values = DEFAULTS.duplicate()
	for key: String in DEFAULTS:
		_announce(key, before.get(key))
	for action: String in _keys:
		InputBindings.restore(action)
	_keys.clear()


## Volume, window and UI scale: the parts the engine holds. Safe to call again after a
## change. `root` is the main window.
static func apply(root: Window) -> void:
	var bus := AudioServer.get_bus_index(&"Master")
	var volume := float(value("volume"))
	AudioServer.set_bus_mute(bus, volume <= 0.001)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volume, 0.001)))
	root.content_scale_factor = float(value("ui_scale"))
	if DisplayServer.get_name() == "headless":
		return
	var full := bool(value("fullscreen"))
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if full else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)


## Rebinds `action` to one key (its other keys go) and remembers it.
static func bind(action: String, physical: Key) -> void:
	_keys[action] = physical
	_bind_now(action, physical)


## The key the player chose for `action`, or KEY_NONE.
static func bound_key(action: String) -> int:
	return _keys.get(action, KEY_NONE)


## Puts the player's keys into the InputMap. Before modules register their defaults, so a
## chosen key wins (registering skips actions that already exist); again after, for actions
## a module had already registered.
static func apply_keys() -> void:
	for action: String in _keys:
		_bind_now(action, _keys[action] as Key)


static func _bind_now(action: String, physical: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = physical
	InputMap.action_add_event(action, ev)


static func _announce(key: String, before: Variant) -> void:
	var now: Variant = value(key)
	if typeof(now) != typeof(before) or now != before:
		EventBus.publish(&"settings.changed", {"key": key, "value": now})


static func _clamp() -> void:
	_values["mouse_scale"] = clampf(float(_values["mouse_scale"]), MOUSE_MIN, MOUSE_MAX)
	_values["fov_offset"] = clampf(float(_values["fov_offset"]), FOV_MIN, FOV_MAX)
	_values["volume"] = clampf(float(_values["volume"]), 0.0, 1.0)
	_values["ui_scale"] = clampf(float(_values["ui_scale"]), UI_MIN, UI_MAX)
	_values["fullscreen"] = bool(_values["fullscreen"])
	_values["blood"] = bool(_values["blood"])
