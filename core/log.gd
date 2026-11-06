class_name GameLog
extends Node
## Categorised logger, registered as the `Log` autoload. Errors go to the engine log so the
## gate catches them; tests that expect an error capture it instead.

enum Level { DEBUG, INFO, WARN, ERROR }

var min_level: Level = Level.INFO

var _capturing: bool = false
var _captured: Array[Dictionary] = []


func debug(category: StringName, message: String) -> void:
	_write(Level.DEBUG, category, message)


func info(category: StringName, message: String) -> void:
	_write(Level.INFO, category, message)


func warn(category: StringName, message: String) -> void:
	_write(Level.WARN, category, message)


func error(category: StringName, message: String) -> void:
	_write(Level.ERROR, category, message)


## Tests only: warnings and errors are recorded instead of pushed, so an expected
## error does not fail the gate's log scan.
func begin_capture() -> void:
	_capturing = true
	_captured.clear()


func end_capture() -> Array[Dictionary]:
	_capturing = false
	var out: Array[Dictionary] = _captured.duplicate()
	_captured.clear()
	return out


func _write(level: Level, category: StringName, message: String) -> void:
	if level < min_level:
		return
	if _capturing and level >= Level.WARN:
		_captured.append({"level": level, "category": category, "message": message})
		return
	var line := "[%s] %s: %s" % [Level.keys()[level], category, message]
	match level:
		Level.ERROR:
			push_error(line)
		Level.WARN:
			push_warning(line)
		_:
			print(line)
