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
	for i in spray.live_count():
		if spray.drop_position(i).z < -0.05:
			ahead += 1
	assert_int(ahead).is_equal(10)
	spray.advance(0.45)
	assert_int(spray.live_count()).is_equal(0)
