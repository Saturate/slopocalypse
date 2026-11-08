class_name PlayerProfile
extends RefCounted
## Who this player is to a server: the name they picked and a random key made once per
## install, kept in user://profile.json. The server ties saved gear to the name and only hands
## it back to the key that first used it. `--name=NAME` on the command line wins over the
## file (local test runs with two windows on one machine).

const FILE := "user://profile.json"
const DEFAULT_NAME := "Player"
const KEY_BYTES := 16

var name := DEFAULT_NAME
var key := ""


static func load_from(path: String = FILE) -> PlayerProfile:
	var profile := PlayerProfile.new()
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			profile.name = str((parsed as Dictionary).get("name", DEFAULT_NAME))
			profile.key = str((parsed as Dictionary).get("key", ""))
	if profile.key.length() < KEY_BYTES * 2:
		profile.key = Crypto.new().generate_random_bytes(KEY_BYTES).hex_encode()
		profile.save(path)
	return profile


func save(path: String = FILE) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		Log.warn(&"net", "could not write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify({"name": name, "key": key}, "  "))


## The name to join with: `--name=` if given, else the saved one.
static func name_from_args(args: PackedStringArray, fallback: String) -> String:
	for arg in args:
		if arg.begins_with("--name="):
			return arg.trim_prefix("--name=")
	return fallback
