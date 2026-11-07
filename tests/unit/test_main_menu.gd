extends GdUnitTestSuite
## The menu turns clicks into a session choice; Boot and Net act on it.

const SAVED := "user://test_menu_servers.json"

var _menu: MainMenu


func before_test() -> void:
	_menu = auto_free(MainMenu.new())
	_menu.save_path = SAVED
	_menu.servers = ServerList.new()
	_menu.servers.remember("old.example:7000")
	add_child(_menu)


func after_test() -> void:
	if FileAccess.file_exists(SAVED):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVED))


func test_solo_asks_for_solo() -> void:
	var got: Array[String] = []
	_menu.solo_requested.connect(func() -> void: got.append("solo"))
	_menu.button(&"Solo").pressed.emit()
	assert_array(got).contains_exactly(["solo"])


func test_host_asks_to_host_on_the_chosen_port() -> void:
	var ports: Array[int] = []
	_menu.host_requested.connect(func(p: int) -> void: ports.append(p))
	_menu.button(&"Host").pressed.emit()
	assert_array(ports).contains_exactly([NetSession.DEFAULT_PORT])


func test_join_uses_the_typed_address_and_remembers_it() -> void:
	var targets: Array[String] = []
	_menu.join_requested.connect(func(h: String, p: int) -> void: targets.append("%s:%d" % [h, p]))
	_menu.address_field().text = "100.64.1.2"
	_menu.button(&"Join").pressed.emit()
	assert_array(targets).contains_exactly(["100.64.1.2:%d" % NetSession.DEFAULT_PORT])
	assert_str(ServerList.load_from(SAVED, "").addresses()[0]).is_equal("100.64.1.2")


func test_a_bad_address_says_so_and_joins_nothing() -> void:
	var targets: Array[String] = []
	_menu.join_requested.connect(func(h: String, _p: int) -> void: targets.append(h))
	_menu.address_field().text = "not an address"
	_menu.button(&"Join").pressed.emit()
	assert_array(targets).is_empty()
	assert_bool(_menu.message_label().visible).is_true()


func test_the_last_server_is_filled_in_and_saved_ones_are_listed() -> void:
	assert_str(_menu.address_field().text).is_equal("old.example:7000")
	var picked: Button = _menu.find_child("Server0", true, false)
	assert_object(picked).is_not_null()


func test_a_saved_server_joins_with_one_click() -> void:
	var targets: Array[String] = []
	_menu.join_requested.connect(func(h: String, p: int) -> void: targets.append("%s:%d" % [h, p]))
	(_menu.find_child("Server0", true, false) as Button).pressed.emit()
	assert_array(targets).contains_exactly(["old.example:7000"])


func test_why_the_last_session_ended_is_shown() -> void:
	var menu: MainMenu = auto_free(MainMenu.new())
	menu.servers = ServerList.new()
	menu.message = "Could not reach x:1."
	add_child(menu)
	assert_bool(menu.message_label().visible).is_true()
	assert_str(menu.message_label().text).contains("x:1")


func test_tailscale_addresses_come_first() -> void:
	var ranked := MainMenu.rank_addresses(PackedStringArray(["192.168.1.5", "127.0.0.1", "fe80::1", "100.70.3.4", "10.0.0.2"]))
	assert_array(ranked).contains_exactly(["100.70.3.4", "192.168.1.5", "10.0.0.2"])
