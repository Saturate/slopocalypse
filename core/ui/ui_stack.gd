class_name UiStack
extends RefCounted
## The screens that are open, in the order they opened; the last is on top. It is the one
## place that sets the mouse mode: free while any screen is open, captured when the last
## one closes and a local player is playing. Esc (`ui_cancel`) belongs to the top screen
## only, so a screen opened over another closes first.
##
## Static rather than an autoload: core's autoload list is an architecture rule, and this
## needs no node. Boot clears it whenever the main scene (re)loads.

static var _open: Array[Object] = []
## Set by the local player's input while it exists: with no screen open, the mouse belongs
## to the game. In the main menu nothing sets it and the mouse stays free.
static var _captures_when_empty := false


static func push(screen: Object) -> void:
	_prune()
	_open.erase(screen)
	_open.append(screen)
	_apply()


static func pop(screen: Object) -> void:
	_open.erase(screen)
	_prune()
	_apply()


static func is_open(screen: Object) -> bool:
	return _open.has(screen)


static func is_top(screen: Object) -> bool:
	_prune()
	return not _open.is_empty() and _open.back() == screen


## True while any screen is open: gameplay input (moving, shooting, prompts) waits.
static func is_blocking() -> bool:
	_prune()
	return not _open.is_empty()


static func count() -> int:
	_prune()
	return _open.size()


static func set_captures_when_empty(on: bool) -> void:
	_captures_when_empty = on
	_apply()


## What the mouse should be now.
static func mouse_mode() -> Input.MouseMode:
	if _captures_when_empty and _open.is_empty():
		return Input.MOUSE_MODE_CAPTURED
	return Input.MOUSE_MODE_VISIBLE


## For the screen on top: is `event` its Esc (or gamepad back)?
static func is_cancel(event: InputEvent) -> bool:
	return event.is_action_pressed(&"ui_cancel") and not event.is_echo()


static func clear() -> void:
	_open.clear()
	_captures_when_empty = false
	_apply()


## A freed screen that never popped itself must not hold the mouse forever.
static func _prune() -> void:
	for i in range(_open.size() - 1, -1, -1):
		if not is_instance_valid(_open[i]):
			_open.remove_at(i)


static func _apply() -> void:
	Input.mouse_mode = mouse_mode()
