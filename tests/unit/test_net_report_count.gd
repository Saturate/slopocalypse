extends GdUnitTestSuite
## --net-report-after counts physics frames from when the session is under way, not from
## launch: the smoke tests start a server and its clients seconds apart, a slow machine loads
## for seconds, and a client builds the server's world only after joining.

var _net: Node


func before_test() -> void:
	_net = auto_free((load("res://core/net.gd") as GDScript).new())
	_net.set(&"_report_after", 1000)


func _ticks(count: int) -> void:
	for i in count:
		_net.call(&"_physics_tick", 1.0 / 60.0)


func test_nothing_counts_before_the_first_peer() -> void:
	_ticks(30)
	assert_int(int(_net.get(&"_frames"))).is_equal(0)


func test_a_server_counts_once_someone_is_there() -> void:
	_net.set(&"mode", NetSession.Mode.SERVER)
	_ticks(30)
	_net.set(&"_had_peers", true)
	_ticks(20)
	assert_int(int(_net.get(&"_frames"))).is_equal(20)


func test_a_client_counts_only_once_its_player_is_in_the_world() -> void:
	_net.set(&"mode", NetSession.Mode.CLIENT)
	_net.set(&"_had_peers", true)
	_ticks(30)
	assert_int(int(_net.get(&"_frames"))).is_equal(0)
	_net.set(&"_in_play", true)
	_ticks(20)
	assert_int(int(_net.get(&"_frames"))).is_equal(20)


func test_a_server_waits_for_each_connected_client_that_has_not_reported() -> void:
	var peers := PackedInt32Array([5, 9])
	assert_array(NetSession.unreported(peers, {})).contains_exactly([5, 9])
	assert_array(NetSession.unreported(peers, {9: true})).contains_exactly([5])
	# One that reported and left is not waited for, nor counted against the rest.
	assert_array(NetSession.unreported(PackedInt32Array([5]), {5: true, 9: true})).is_empty()


func test_a_solo_tool_run_that_never_reaches_its_server_gives_up() -> void:
	_net.set(&"mode", NetSession.Mode.SOLO)
	var seconds := float(NetSession.FIRST_JOIN_SECONDS)
	assert_bool(_net.call(&"_waited_too_long", seconds - 1.0)).is_false()
	assert_bool(_net.call(&"_waited_too_long", 1.0)).is_true()


func test_a_tool_server_nobody_joins_gives_up() -> void:
	_net.set(&"mode", NetSession.Mode.SERVER)
	assert_bool(_net.call(&"_waited_too_long", float(NetSession.FIRST_JOIN_SECONDS))).is_true()


func test_a_connected_session_never_gives_up() -> void:
	_net.set(&"mode", NetSession.Mode.SOLO)
	_net.set(&"_had_peers", true)
	assert_bool(_net.call(&"_waited_too_long", 1000.0)).is_false()


func test_a_plain_client_is_left_to_its_join_timeout() -> void:
	_net.set(&"mode", NetSession.Mode.CLIENT)
	assert_bool(_net.call(&"_waited_too_long", 1000.0)).is_false()
