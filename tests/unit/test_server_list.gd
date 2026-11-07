extends GdUnitTestSuite

const SAVED := "user://test_servers.json"
const DEFAULTS := "user://test_default_servers.json"


func after_test() -> void:
	for path in [SAVED, DEFAULTS]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_an_address_without_a_port_uses_the_default() -> void:
	var a := ServerList.parse_address(" 100.64.0.7 ")
	assert_bool(a["ok"]).is_true()
	assert_str(a["host"]).is_equal("100.64.0.7")
	assert_int(a["port"]).is_equal(NetSession.DEFAULT_PORT)


func test_an_address_with_a_port_keeps_it() -> void:
	var a := ServerList.parse_address("game.example.net:9000")
	assert_str(a["host"]).is_equal("game.example.net")
	assert_int(a["port"]).is_equal(9000)


func test_bad_addresses_are_refused() -> void:
	for bad in ["", "   ", "host:abc", "host:0", "host:70000", ":7777", "a b"]:
		assert_bool(ServerList.parse_address(bad)["ok"]).override_failure_message(bad).is_false()


func test_remembering_puts_the_address_first_once() -> void:
	var list := ServerList.new()
	list.remember("a")
	list.remember("b")
	list.remember("a")
	assert_array(list.addresses()).contains_exactly(["a", "b"])


func test_the_list_stays_short() -> void:
	var list := ServerList.new()
	for i in ServerList.MAX_RECENT + 3:
		list.remember("host%d" % i)
	assert_int(list.addresses().size()).is_equal(ServerList.MAX_RECENT)


func test_saved_servers_come_back_after_a_restart() -> void:
	var list := ServerList.new()
	list.remember("first")
	list.remember("second")
	list.save(SAVED)
	var again := ServerList.load_from(SAVED, DEFAULTS)
	assert_array(again.addresses()).contains_exactly(["second", "first"])


func test_shipped_servers_appear_after_your_own() -> void:
	var f := FileAccess.open(DEFAULTS, FileAccess.WRITE)
	f.store_string(JSON.stringify({"servers": ["friends.example:7777", "mine"]}))
	f.close()
	var list := ServerList.new()
	list.remember("mine")
	list.save(SAVED)
	var loaded := ServerList.load_from(SAVED, DEFAULTS)
	assert_array(loaded.addresses()).contains_exactly(["mine", "friends.example:7777"])


func test_missing_or_broken_files_give_an_empty_list() -> void:
	var f := FileAccess.open(SAVED, FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	assert_array(ServerList.load_from(SAVED, DEFAULTS).addresses()).is_empty()
