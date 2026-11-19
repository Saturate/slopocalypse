extends GdUnitTestSuite
## --net-report-after counts physics frames from the session's first peer, not from launch:
## the smoke tests start a server and its clients seconds apart, and a slow machine loads
## for seconds, so counting from launch let a server stop before a client had reported.

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


func test_frames_count_once_someone_is_there() -> void:
	_ticks(30)
	_net.set(&"_had_peers", true)
	_ticks(20)
	assert_int(int(_net.get(&"_frames"))).is_equal(20)
