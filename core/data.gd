class_name GameData
extends Node
## Loads JSON gameplay data, registered as the `Data` autoload. Bad data fails loudly at
## load time, naming the file and field, instead of surfacing later as a wrong number.


## Folder next to the exported game whose files replace the built-in data, so values can
## be tuned without rebuilding: `tweaks/modules/enemies/data/enemies.json` replaces
## `res://modules/enemies/data/enemies.json`. Empty (off) when running from the editor,
## where the project files are edited directly.
var tweaks_root := OS.get_executable_path().get_base_dir().path_join("tweaks") if OS.has_feature("template") else ""


## The file to read for `path`: its copy in `root` if there is one, otherwise `path`.
static func tweaked(path: String, root: String) -> String:
	if root.is_empty() or not path.begins_with("res://"):
		return path
	var copy := root.path_join(path.trim_prefix("res://"))
	return copy if FileAccess.file_exists(copy) else path


## Returns the parsed root object, or null after logging why.
func load_json(path: String) -> Variant:
	var from := tweaked(path, tweaks_root)
	if from != path:
		Log.info(&"data", "%s: using the tweaked copy %s" % [path, from])
		path = from
	if not FileAccess.file_exists(path):
		Log.error(&"data", "%s: file not found" % path)
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		Log.error(&"data", "%s: invalid JSON at line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	if typeof(json.data) != TYPE_DICTIONARY:
		Log.error(&"data", "%s: root must be an object" % path)
		return null
	return json.data


## Checks required fields and their types. JSON numbers always parse as float, so
## numeric fields are declared as TYPE_FLOAT.
func require(path: String, dict: Dictionary, fields: Dictionary) -> bool:
	var ok := true
	for field: String in fields:
		var expected: int = fields[field]
		if not dict.has(field):
			Log.error(&"data", "%s: missing required field '%s'" % [path, field])
			ok = false
		elif typeof(dict[field]) != expected:
			Log.error(&"data", "%s: field '%s' should be %s, got %s" % [path, field, type_string(expected), type_string(typeof(dict[field]))])
			ok = false
	return ok
