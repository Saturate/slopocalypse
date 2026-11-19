extends GdUnitTestSuite
## The spray is one pool of drops: never more than `max_drops` fly, the oldest are reused
## first, they leave along the shot, and they are gone after `drop_seconds`.

var _cfg: Dictionary


func before_test() -> void:
	_cfg = BloodEffects.config().duplicate()
	_cfg["max_drops"] = 20.0
	_cfg["drop_seconds"] = 0.5


func _spray() -> BloodSpray:
	var spray: BloodSpray = auto_free(BloodSpray.new())
	spray.setup(_cfg)
	add_child(spray)
	spray.set_process(false)
	return spray


func test_drops_never_pass_the_cap() -> void:
	var spray := _spray()
	spray.spray(Vector3.ZERO, Vector3.FORWARD, 15)
	assert_int(spray.live_count()).is_equal(15)
	spray.spray(Vector3.ZERO, Vector3.FORWARD, 15)
	assert_int(spray.live_count()).is_equal(20)
	assert_int(spray.multimesh.instance_count).is_equal(20)


func test_drops_fly_along_the_shot_and_are_gone_after_their_time() -> void:
	var spray := _spray()
	spray.spray(Vector3.ZERO, Vector3.FORWARD, 10)
	spray.advance(0.1)
	var ahead := 0
	for at in spray.live_positions():
		if at.z < -0.05:
			ahead += 1
	assert_int(ahead).is_equal(10)
	spray.advance(0.45)
	assert_int(spray.live_count()).is_equal(0)


func test_the_oldest_drops_are_reused_once_the_ring_is_full() -> void:
	var spray := _spray()
	spray.spray(Vector3.ZERO, Vector3.FORWARD, 20)
	spray.advance(0.2)
	spray.spray(Vector3(0, 10, 0), Vector3.FORWARD, 5)
	var fresh := 0
	for at in spray.live_positions():
		if at.y > 9.0:
			fresh += 1
	assert_int(fresh).is_equal(5)
	assert_int(spray.live_count()).is_equal(20)
	# The 15 older ones go at their time; the 5 new ones fly on.
	spray.advance(0.35)
	assert_int(spray.live_count()).is_equal(5)


func test_clear_drops_every_drop_in_flight() -> void:
	var spray := _spray()
	spray.spray(Vector3.ZERO, Vector3.FORWARD, 8)
	spray.clear()
	assert_int(spray.live_count()).is_equal(0)
	assert_int(spray.multimesh.visible_instance_count).is_equal(0)
