extends GdUnitTestSuite
## Where the web page listens (#448): `--web-port=` / `--web-bind=` on the command line, else
## WEB_PORT / WEB_BIND in the environment (the Docker image), else the game's port on every
## address. A setting that makes no sense keeps the page off rather than guessing.

const WEB := "res://modules/web/web_module.gd"
const GAME_PORT := 7777


func _options(args: Array[String], env: Dictionary = {}) -> Dictionary:
	return (load(WEB) as GDScript).call(&"listen_options", PackedStringArray(args), env, GAME_PORT)


func test_by_default_the_page_is_on_the_game_port_on_every_address() -> void:
	var o := _options([])
	assert_str(str(o["error"])).is_empty()
	assert_int(int(o["port"])).is_equal(GAME_PORT)
	assert_str(str(o["bind"])).is_equal("*")


func test_the_command_line_sets_port_and_address() -> void:
	var o := _options(["--web", "--web-port=8080", "--web-bind=127.0.0.1"])
	assert_str(str(o["error"])).is_empty()
	assert_int(int(o["port"])).is_equal(8080)
	assert_str(str(o["bind"])).is_equal("127.0.0.1")


func test_the_environment_sets_them_when_the_command_line_does_not() -> void:
	var o := _options(["--web"], {"WEB_PORT": "8081", "WEB_BIND": "::1"})
	assert_int(int(o["port"])).is_equal(8081)
	assert_str(str(o["bind"])).is_equal("::1")
	var flags_win := _options(["--web-bind=10.0.0.5"], {"WEB_BIND": "127.0.0.1"})
	assert_str(str(flags_win["bind"])).is_equal("10.0.0.5")
	# An empty variable is the same as none.
	assert_str(str(_options([], {"WEB_BIND": "", "WEB_PORT": ""})["bind"])).is_equal("*")


func test_a_bad_address_or_port_keeps_the_page_off() -> void:
	for args: Array[String] in [["--web-bind=localhost:80"], ["--web-bind=my server"], ["--web-port=0"], ["--web-port=70000"], ["--web-port=http"]]:
		assert_str(str(_options(args)["error"])).override_failure_message("%s was accepted" % [args]).is_not_empty()
	assert_str(str(_options([], {"WEB_BIND": "everywhere"})["error"])).is_not_empty()
