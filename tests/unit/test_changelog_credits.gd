extends GdUnitTestSuite
## The changelog and credits readers, and their screens on the title.

const FIXTURE := """# Changelog

## 0.2.0 - 2026-11-09

#### Press F3 for live performance numbers.

Felled trees break with a splintered stump.

### Internal

#### Developers can benchmark the game.

## 0.1.0 - 2026-11-08

#### Servers can run from a Docker image.
"""


func after_test() -> void:
	UiStack.clear()


func test_releases_come_newest_first_without_internal_changes() -> void:
	var releases := Changelog.parse(FIXTURE)
	assert_int(releases.size()).is_equal(2)
	assert_str(str(releases[0]["version"])).is_equal("0.2.0")
	assert_str(str(releases[0]["date"])).is_equal("2026-11-09")
	assert_array(releases[0]["changes"]).contains_exactly(["Press F3 for live performance numbers.", "Felled trees break with a splintered stump."])
	assert_array(releases[1]["changes"]).contains_exactly(["Servers can run from a Docker image."])


func test_the_real_changelog_reads() -> void:
	var releases := Changelog.load_releases()
	assert_int(releases.size()).is_greater(0)
	for release: Dictionary in releases:
		assert_str(str(release["version"])).is_not_empty()


func test_credits_list_every_shipped_row_of_the_licence_table() -> void:
	var text := FileAccess.get_file_as_string(Credits.LICENSES)
	var rows := 0
	for line: String in text.split("\n"):
		if line.begins_with("| ") and not line.begins_with("| Path") and not line.begins_with("| ---") and not line.contains("dev only") and not line.contains("dev tool"):
			rows += 1
	var parts := Credits.third_party()
	assert_int(parts.size()).is_equal(rows)
	for part: Dictionary in parts:
		assert_str(str(part["what"])).is_not_empty()
		assert_str(str(part["licence"])).is_not_empty()
		assert_bool(str(part["what"]).contains("`")).is_false()


func test_people_come_from_data() -> void:
	var people := Credits.people()
	assert_bool((people.get("people", []) as Array).is_empty()).is_false()


func test_title_opens_the_changelog_and_credits_and_esc_goes_back() -> void:
	var menu: MainMenu = auto_free(MainMenu.new())
	menu.servers = ServerList.new()
	menu.profile_path = "user://test_credits_profile.json"
	add_child(menu)
	for id: StringName in [&"Changelog", &"Credits"]:
		menu.button(id).pressed.emit()
		assert_str(menu.open_screen()).is_equal(String(id))
		var ev := InputEventAction.new()
		ev.action = &"ui_cancel"
		ev.pressed = true
		get_viewport().push_input(ev)
		assert_str(menu.open_screen()).is_equal("")


func test_credits_stop_rolling_when_the_player_scrolls() -> void:
	var credits: CreditsScreen = auto_free(CreditsScreen.new())
	add_child(credits)
	assert_bool(credits.is_rolling()).is_true()
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	credits.scroll.gui_input.emit(wheel)
	assert_bool(credits.is_rolling()).is_false()
	credits.restart()
	assert_bool(credits.is_rolling()).is_true()
