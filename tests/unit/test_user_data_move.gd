extends GdUnitTestSuite
## After the rename the player's profile key, server list and saves come along from the old
## user folder, once, and never overwrite anything already in the new one.

const ROOT := "user://test_user_data_move"

var _old: String
var _new: String


func before_test() -> void:
	var root := ProjectSettings.globalize_path(ROOT)
	_remove(root)
	_old = root.path_join("Outpost")
	_new = root.path_join("Slopocalypse")
	DirAccess.make_dir_recursive_absolute(_old.path_join("saves/backup"))
	DirAccess.make_dir_recursive_absolute(_new.path_join("logs"))
	_write(_old.path_join("profile.json"), "key")
	_write(_old.path_join("servers.json"), "list")
	_write(_old.path_join("saves/world.db"), "world")
	_write(_old.path_join("saves/backup/world.db"), "older")


func after_test() -> void:
	_remove(ProjectSettings.globalize_path(ROOT))


func test_copies_profile_servers_and_saves_into_a_fresh_folder() -> void:
	assert_int(UserDataMove.copy_missing(_old, _new)).is_equal(3)
	assert_str(FileAccess.get_file_as_string(_new.path_join("profile.json"))).is_equal("key")
	assert_str(FileAccess.get_file_as_string(_new.path_join("servers.json"))).is_equal("list")
	assert_str(FileAccess.get_file_as_string(_new.path_join("saves/backup/world.db"))).is_equal("older")
	# The old folder stays as it was, as a backup.
	assert_bool(FileAccess.file_exists(_old.path_join("saves/world.db"))).is_true()


func test_leaves_a_folder_that_already_has_player_files_alone() -> void:
	_write(_new.path_join("profile.json"), "new key")
	assert_int(UserDataMove.copy_missing(_old, _new)).is_equal(0)
	assert_str(FileAccess.get_file_as_string(_new.path_join("profile.json"))).is_equal("new key")
	assert_bool(DirAccess.dir_exists_absolute(_new.path_join("saves"))).is_false()


func test_nothing_to_do_without_an_old_folder() -> void:
	_remove(_old)
	assert_int(UserDataMove.copy_missing(_old, _new)).is_equal(0)


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)


func _remove(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	for dir in DirAccess.get_directories_at(path):
		_remove(path.path_join(dir))
	DirAccess.remove_absolute(path)
