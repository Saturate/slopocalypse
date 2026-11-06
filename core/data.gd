class_name GameData
extends Node
## Loads JSON gameplay data, registered as the `Data` autoload. Bad data fails loudly at
## load time, naming the file and field, instead of surfacing later as a wrong number.


## Returns the parsed root object, or null after logging why.
func load_json(path: String) -> Variant:
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
