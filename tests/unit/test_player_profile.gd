extends GdUnitTestSuite
## The profile is who this install is to a server: a name and a key made once.

const PATH := "user://test_profile.json"


func after_test() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func test_a_new_install_gets_a_key_that_stays() -> void:
	var first := PlayerProfile.load_from(PATH)
	assert_int(first.key.length()).is_equal(PlayerProfile.KEY_BYTES * 2)
	assert_str(first.name).is_equal(PlayerProfile.DEFAULT_NAME)
	assert_str(PlayerProfile.load_from(PATH).key).is_equal(first.key)


func test_the_name_is_saved_with_the_key() -> void:
	var profile := PlayerProfile.load_from(PATH)
	profile.name = "Ranger"
	profile.save(PATH)
	var again := PlayerProfile.load_from(PATH)
	assert_str(again.name).is_equal("Ranger")
	assert_str(again.key).is_equal(profile.key)


func test_name_on_the_command_line_wins() -> void:
	assert_str(PlayerProfile.name_from_args(PackedStringArray(["--bot=walk", "--name=Two"]), "One")).is_equal("Two")
	assert_str(PlayerProfile.name_from_args(PackedStringArray(["--bot=walk"]), "One")).is_equal("One")
