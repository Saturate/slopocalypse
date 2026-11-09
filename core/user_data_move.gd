class_name UserDataMove
extends RefCounted
## The game used to be called Outpost, and Godot names the user folder after the project, so
## the rename moved it. On first launch under the new name this copies the player's own files
## across: the profile key matters most, since the server only hands saved gear back to it.
## Logs are left behind; Godot has already started new ones by the time any script runs.

const OLD_NAME := "Outpost"
const ITEMS: Array[String] = ["profile.json", "servers.json", "saves"]


## Copies ITEMS from the old project's user folder into this one, once: only when this folder
## has none of them yet. Returns how many were copied.
static func run() -> int:
	var here := OS.get_user_data_dir()
	return copy_missing(here.get_base_dir().path_join(OLD_NAME), here)


static func copy_missing(from: String, to: String) -> int:
	if from == to or not DirAccess.dir_exists_absolute(from):
		return 0
	for item in ITEMS:
		if FileAccess.file_exists(to.path_join(item)) or DirAccess.dir_exists_absolute(to.path_join(item)):
			return 0
	var copied := 0
	for item in ITEMS:
		var source := from.path_join(item)
		if FileAccess.file_exists(source):
			if DirAccess.copy_absolute(source, to.path_join(item)) == OK:
				copied += 1
		elif DirAccess.dir_exists_absolute(source) and _copy_dir(source, to.path_join(item)):
			copied += 1
	return copied


static func _copy_dir(from: String, to: String) -> bool:
	if DirAccess.make_dir_recursive_absolute(to) != OK:
		return false
	for file in DirAccess.get_files_at(from):
		if DirAccess.copy_absolute(from.path_join(file), to.path_join(file)) != OK:
			return false
	for dir in DirAccess.get_directories_at(from):
		if not _copy_dir(from.path_join(dir), to.path_join(dir)):
			return false
	return true
