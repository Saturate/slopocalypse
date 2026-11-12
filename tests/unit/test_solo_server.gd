extends GdUnitTestSuite


func test_args_start_a_private_headless_server_that_quits_when_empty() -> void:
	var args := SoloServer.server_args(7801, PackedStringArray(), "C:/game", "C:/logs/solo.log")
	assert_array(args).contains_exactly([
		"--headless", "--path", "C:/game", "--log-file", "C:/logs/solo.log", "--",
		"--server=7801", "--bind=127.0.0.1", "--quit-when-empty", "--log-file=C:/logs/solo.log",
	])


func test_exported_builds_need_no_project_path() -> void:
	var args := SoloServer.server_args(7801, PackedStringArray(), "", "log.txt")
	assert_bool(args.has("--path")).is_false()


func test_feature_flags_carry_over_but_client_only_args_do_not() -> void:
	var user := PackedStringArray(["--flags=car:off", "--bot=walk", "--all-optional-off", "--net-report-after=900"])
	var args := SoloServer.server_args(7801, user, "", "log.txt")
	assert_bool(args.has("--flags=car:off")).is_true()
	assert_bool(args.has("--all-optional-off")).is_true()
	assert_bool(args.has("--bot=walk")).is_false()
	assert_bool(args.has("--net-report-after=900")).is_false()


func test_the_test_range_flag_reaches_the_server() -> void:
	var args := SoloServer.server_args(7801, PackedStringArray(["--range", "--bot=range"]), "", "log.txt")
	assert_bool(args.has("--range")).is_true()
	assert_bool(args.has("--bot=range")).is_false()


func test_picks_a_port_nothing_else_is_bound_to() -> void:
	# Take whichever port is free first: a running solo game may already hold FIRST_PORT.
	var first := SoloServer.pick_port()
	var taken := PacketPeerUDP.new()
	assert_int(taken.bind(first, "127.0.0.1")).is_equal(OK)
	var port := SoloServer.pick_port()
	taken.close()
	assert_int(port).is_not_equal(first)
	assert_int(port).is_between(SoloServer.FIRST_PORT, SoloServer.FIRST_PORT + SoloServer.PORT_TRIES)


func test_a_hosted_server_listens_on_every_interface() -> void:
	var args := SoloServer.server_args(7777, PackedStringArray(), "", "log.txt", "")
	assert_bool(args.has("--server=7777")).is_true()
	assert_bool(args.has("--quit-when-empty")).is_true()
	for a in args:
		assert_bool(a.begins_with("--bind")).is_false()


func test_the_menu_shows_only_for_a_player_who_gave_no_mode() -> void:
	assert_bool(NetSession.wants_menu(PackedStringArray(), false)).is_true()
	assert_bool(NetSession.wants_menu(PackedStringArray(), true)).is_false()
	for args: Array in [["--connect=1.2.3.4"], ["--server"], ["--solo"], ["--bot=walk"], ["--net-report-after=60"]]:
		assert_bool(NetSession.wants_menu(PackedStringArray(args), false)).override_failure_message(str(args)).is_false()
