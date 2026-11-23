class_name Settings
extends RefCounted
## The player's own settings, kept in user://settings.cfg: mouse sensitivity, field of view,
## volume, fullscreen, UI scale and key bindings, plus the settings modules register in their
## module.json (`settings`; the compass strip, blood, the partner marker...). Gameplay code
## asks for the values (`mouse_scale()`, `value(key)`); boot applies the rest once at
## start.
##
## A module's settings go with its folder (docs/decisions/0019): core names none of them. A
## value in the file that no present module registers (its folder is gone) is kept as it was
## and written back, so putting the module back finds the player's choice.
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

## The engine-wide settings core owns.
const DEFAULTS := {
	"mouse_scale": 1.0,
	"fov_offset": 0.0,
	"volume": 1.0,
	"fullscreen": false,
	"ui_scale": 1.0,
}

## key -> {key, type, default, label, order, module, flag}, from the modules present.
static var _registered: Dictionary[String, Dictionary] = {}
static var _discovered := false
static var _values: Dictionary = {}
## Values in the file for keys nothing registers now, written back untouched.
static var _kept: Dictionary = {}
## action -> physical keycode the player chose.
static var _keys: Dictionary[String, int] = {}
static var _path := PATH


static func load_from(path := PATH) -> void:
	_ensure_registered()
	_path = path
	_values = defaults()
	_kept.clear()
	_keys.clear()
	var file := ConfigFile.new()
	if file.load(path) != OK:
		return
	if file.has_section("game"):
		for key: String in file.get_section_keys("game"):
			var v: Variant = file.get_value("game", key)
			if _values.has(key):
				_values[key] = v
			else:
				_kept[key] = v
	_clamp()
	if file.has_section("keys"):
		for action: String in file.get_section_keys("keys"):
			_keys[action] = int(file.get_value("keys", action, KEY_NONE))


## Registers the settings of `modules` (every module present, flag on or off), replacing
## what was registered. A key core owns or another module took is an error and skipped.
## Boot does this from modules/ on first use; tests hand in fixtures.
static func use_modules(modules: Array[ModuleLoader.ModuleInfo]) -> void:
	_discovered = true
	_registered.clear()
	for m in modules:
		for entry: Dictionary in m.settings:
			var key: String = entry["key"]
			if DEFAULTS.has(key) or _registered.has(key):
				var owner: String = "core" if DEFAULTS.has(key) else String(_registered[key]["module"])
				Log.error(&"settings", "module '%s' registers setting '%s', which %s already owns" % [m.id, key, owner])
				continue
			_registered[key] = entry.merged({"module": m.id, "flag": m.flag})
	var before := _values
	_values = defaults()
	for key: String in before:
		if _values.has(key):
			_values[key] = before[key]
		else:
			_kept[key] = before[key]
	for key: String in _kept.keys():
		if _values.has(key):
			_values[key] = _kept[key]
			_kept.erase(key)
	_clamp()


## Registers from modules/ again on next use (after a test handed in fixtures). The values of
## the forgotten registrations go too, so a fixture's key never reaches a saved file.
static func forget_modules() -> void:
	for key: String in _registered:
		_values.erase(key)
	_discovered = false
	_registered.clear()


## Core's defaults and every registered module setting's.
static func defaults() -> Dictionary:
	_ensure_registered()
	var out := DEFAULTS.duplicate()
	for key: String in _registered:
		out[key] = _registered[key]["default"]
	return out


## Every setting key in use: core's and the registered ones.
static func keys() -> Array[String]:
	var out: Array[String] = []
	out.assign(defaults().keys())
	return out


## A module's registration of `key` ({key, type, default, label, order, module, flag}), or
## empty when no present module registers it.
static func registered(key: String) -> Dictionary:
	_ensure_registered()
	return _registered.get(key, {})


## The registered settings whose module's flag is on, by `order` then key: what the
## settings screen offers. A setting of a module that is off would do nothing.
static func offered() -> Array[Dictionary]:
	_ensure_registered()
	var out: Array[Dictionary] = []
	for key: String in _registered:
		var entry := _registered[key]
		var flag: StringName = entry["flag"]
		if flag == &"" or Features.is_enabled(flag):
			out.append(entry)
	out.sort_custom(_before)
	return out


static func _before(a: Dictionary, b: Dictionary) -> bool:
	if float(a["order"]) != float(b["order"]):
		return float(a["order"]) < float(b["order"])
	return str(a["key"]) < str(b["key"])


static func save() -> void:
	var file := ConfigFile.new()
	for key: String in _kept:
		file.set_value("game", key, _kept[key])
	for key: String in _values:
		file.set_value("game", key, _values[key])
	for action: String in _keys:
		file.set_value("keys", action, _keys[action])
	var err := file.save(_path)
	if err != OK:
		Log.warn(&"settings", "could not save %s (%s)" % [_path, error_string(err)])


static func value(key: String) -> Variant:
	_ensure_registered()
	if _values.has(key):
		return _values[key]
	return _kept.get(key)


## Sets `key` and tells modules that read a setting as they go (gore's blood) through
## `settings.changed` ({key, value}), only when the value really changes.
static func set_value(key: String, v: Variant) -> void:
	_ensure_registered()
	var before: Variant = value(key)
	_values[key] = v
	_clamp()
	_announce(key, before)


static func mouse_scale() -> float:
	return float(value("mouse_scale"))


static func fov_offset() -> float:
	return float(value("fov_offset"))


## Everything back to the game's defaults, keys included. Kept values of absent modules stay.
static func reset() -> void:
	var before := _values.duplicate()
	_values = defaults()
	for key: String in _values:
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


static func _ensure_registered() -> void:
	if _discovered:
		return
	use_modules(ModuleLoader.discover(ModuleLoader.ROOT))


static func _clamp() -> void:
	_values["mouse_scale"] = clampf(float(_values["mouse_scale"]), MOUSE_MIN, MOUSE_MAX)
	_values["fov_offset"] = clampf(float(_values["fov_offset"]), FOV_MIN, FOV_MAX)
	_values["volume"] = clampf(float(_values["volume"]), 0.0, 1.0)
	_values["ui_scale"] = clampf(float(_values["ui_scale"]), UI_MIN, UI_MAX)
	_values["fullscreen"] = bool(_values["fullscreen"])
	for key: String in _registered:
		# A hand-edited file can hold another type; the module reads its own type.
		if typeof(_values[key]) != ModuleLoader.SETTING_TYPES[_registered[key]["type"]]:
			_values[key] = _registered[key]["default"]
