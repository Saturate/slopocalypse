extends GdUnitTestSuite


func test_args_start_a_private_headless_server_that_quits_when_empty() -> void:
	var args := SoloServer.server_args(7801, PackedStringArray(), "C:/game", "C:/logs/solo.log")
	assert_array(args).contains_exactly([
		"--headless", "--path", "C:/game", "--log-file", "C:/logs/solo.log", "--",
		"--server=7801", "--bind=127.0.0.1", "--quit-when-empty",
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


func test_picks_a_port_nothing_else_is_bound_to() -> void:
	var taken := PacketPeerUDP.new()
	assert_int(taken.bind(SoloServer.FIRST_PORT, "127.0.0.1")).is_equal(OK)
	var port := SoloServer.pick_port()
	taken.close()
	assert_int(port).is_not_equal(SoloServer.FIRST_PORT)
	assert_int(port).is_between(SoloServer.FIRST_PORT, SoloServer.FIRST_PORT + SoloServer.PORT_TRIES)
