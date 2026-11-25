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


func test_a_server_counts_once_a_player_has_joined() -> void:
	_net.set(&"mode", NetSession.Mode.SERVER)
	_ticks(30)
	# A connection alone (a client about to be turned away) does not start the clock.
	_net.set(&"_had_peers", true)
	_ticks(10)
	assert_int(int(_net.get(&"_frames"))).is_equal(0)
	_net.set(&"_had_players", true)
	_ticks(20)
	assert_int(int(_net.get(&"_frames"))).is_equal(20)


func test_a_client_counts_only_once_its_player_is_in_the_world() -> void:
	_net.set(&"mode", NetSession.Mode.CLIENT)
	_net.set(&"_had_peers", true)
	_ticks(30)
	assert_int(int(_net.get(&"_frames"))).is_equal(0)
	_net.set(&"_in_play", true)
	_net.set(&"_world_ready", true)
	_ticks(20)
	assert_int(int(_net.get(&"_frames"))).is_equal(20)


# The spawner can hand a client its player seconds before it has built the server's world;
# counting from then, a slow machine reported before its world (and spawn point) existed.
func test_a_client_whose_player_arrived_first_waits_for_its_world() -> void:
	_net.set(&"mode", NetSession.Mode.CLIENT)
	_net.set(&"_in_play", true)
	_ticks(30)
	assert_int(int(_net.get(&"_frames"))).is_equal(0)
	_net.set(&"_world_ready", true)
	_ticks(20)
	assert_int(int(_net.get(&"_frames"))).is_equal(20)


# A server's kick gives the peer time to hang up itself, in ticks: one long frame (loading
# the world) cut the line before the peer had a polled frame to answer in (#552).
func test_a_kicked_peer_is_cut_only_after_kick_seconds_of_ticks() -> void:
	var kicking := {5: NetSession.KICK_SECONDS, 9: NetSession.KICK_SECONDS * 2.0}
	var tick := 1.0 / 60.0
	var cut: Array[int] = []
	var ticks := 0
	while cut.is_empty():
		cut = NetSession.kicks_due(kicking, tick)
		ticks += 1
	assert_array(cut).contains_exactly([5])
	# About KICK_SECONDS of ticks, give or take one for float rounding.
	assert_int(ticks).is_between(roundi(NetSession.KICK_SECONDS / tick) - 1, roundi(NetSession.KICK_SECONDS / tick) + 1)
	# Still being kicked (nothing replicates to them) until the line is cut.
	assert_bool(kicking.has(5)).is_true()
	assert_bool(kicking.has(9)).is_true()


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
