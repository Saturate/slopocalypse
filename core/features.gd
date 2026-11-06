class_name FeatureFlags
extends Node
## Feature flags, registered as the `Features` autoload. Values come from data/features.json
## and can be overridden per run after `--`:
##   --flags=car:off,weapons:on    set individual flags
##   --all-optional-off            every flag off (boot test)

const PATH := "res://data/features.json"

var _flags: Dictionary[StringName, bool] = {}
var _all_off: bool = false


func _ready() -> void:
	reload(OS.get_cmdline_user_args())


func reload(args: PackedStringArray, path: String = PATH) -> void:
	_flags.clear()
	_all_off = false
	_load_file(path)
	for arg in args:
		if arg == "--all-optional-off":
			_all_off = true
		elif arg.begins_with("--flags="):
			_apply_overrides(arg.trim_prefix("--flags="))


func is_enabled(flag: StringName) -> bool:
	if not _flags.has(flag):
		Log.warn(&"features", "unknown flag '%s', treating it as off" % flag)
		return false
	return _flags[flag] and not _all_off


func _load_file(path: String) -> void:
	var data: Variant = Data.load_json(path)
	if not data is Dictionary:
		return
	var root: Dictionary = data
	if not Data.require(path, root, {"flags": TYPE_DICTIONARY}):
		return
	var flags: Dictionary = root["flags"]
	for name: String in flags:
		var value: Variant = flags[name]
		if typeof(value) != TYPE_BOOL:
			Log.error(&"features", "%s: flag '%s' must be true or false" % [path, name])
			continue
		_flags[StringName(name)] = value


func _apply_overrides(spec: String) -> void:
	for pair in spec.split(",", false):
		var parts := pair.split(":")
		if parts.size() != 2 or not parts[1] in ["on", "off"]:
			Log.error(&"features", "bad --flags entry '%s', expected name:on or name:off" % pair)
			continue
		_flags[StringName(parts[0])] = parts[1] == "on"
