extends GdUnitTestSuite
## The players' camp is safe (#420): no squad lands within `camp_margin` of its fence, and a
## soldier never steps in through its gate.

const ENEMIES := "res://modules/enemies/enemies_module.gd"


func _module() -> Node:
	var enemies: Node = auto_free((load(ENEMIES) as GDScript).new())
	add_child(enemies)
	var config := (enemies.get(&"config") as Dictionary)
	# No squads of its own while the test asks for spots.
	config["first_spawn_seconds"] = 1.0e6
	# Spots right up to the camp, so the margin has work to do.
	config["spawn_area"] = [0.0, 250.0]
	return enemies


func _camp(at: Vector3) -> CampLayout:
	var cfg: Dictionary = (Data.load_json(CampLayout.CONFIG) as Dictionary)["camp"]
	return CampLayout.around(at, Vector3.LEFT, cfg)


func test_no_squad_spot_inside_the_margin() -> void:
	var enemies := _module()
	var camp := _camp(Vector3(40.0, 0.0, 10.0))
	EventBus.publish(&"world.ready", {"spawn": camp.spot("respawn").origin + Vector3.UP, "front": camp.spot("car").origin, "forward": camp.out, "camp": camp})
	var margin := float((enemies.get(&"config") as Dictionary)["camp_margin"])
	for i in 300:
		var spot: Vector3 = enemies.call(&"_spread_spot")
		assert_float(camp.distance(spot)).override_failure_message("squad at %s" % spot).is_greater_equal(margin)


func test_a_camp_round_the_spawn_when_the_world_sends_none() -> void:
	var enemies := _module()
	EventBus.publish(&"world.ready", {"spawn": Vector3(0.0, 1.0, 0.0)})
	var camp := CampLayout.of_ready({"spawn": Vector3(0.0, 1.0, 0.0)})
	var margin := float((enemies.get(&"config") as Dictionary)["camp_margin"])
	for i in 100:
		var spot: Vector3 = enemies.call(&"_spread_spot")
		assert_float(camp.distance(spot)).is_greater_equal(margin)


func test_a_soldier_does_not_step_into_the_camp() -> void:
	var camp := _camp(Vector3.ZERO)
	var outside := camp.gate() + camp.out * 0.5
	# Walking in through the gate is refused, walking away along the road is not.
	assert_bool(EnemyBrain.blocks_step(camp, outside, -camp.out)).is_true()
	assert_bool(EnemyBrain.blocks_step(camp, outside, camp.out)).is_false()
	assert_bool(EnemyBrain.blocks_step(camp, outside, camp.right)).is_false()
	# Far off nothing is in the way; inside is not a step in; no camp, no limit.
	assert_bool(EnemyBrain.blocks_step(camp, camp.gate() + camp.out * 30.0, -camp.out)).is_false()
	assert_bool(EnemyBrain.blocks_step(camp, camp.centre, camp.out)).is_false()
	assert_bool(EnemyBrain.blocks_step(null, outside, -camp.out)).is_false()
	# Straight at the gate: nothing of the step is left.
	assert_bool(camp.keep_out_step(outside, -camp.out, EnemyBrain.STEP_AHEAD).is_zero_approx()).is_true()


func test_a_chase_clipping_the_fence_slides_along_it() -> void:
	var camp := _camp(Vector3.ZERO)
	# Beside the right-hand fence, heading in at an angle toward the back.
	var at := camp.point(Vector2(camp.half + 0.5, 2.0))
	var way := (-camp.right - camp.out).normalized()
	var step := camp.keep_out_step(at, way, EnemyBrain.STEP_AHEAD)
	# The part across the fence is gone; the part along it is kept.
	assert_float(step.dot(camp.right)).is_equal_approx(0.0, 0.001)
	assert_float(step.dot(-camp.out)).is_greater(0.5)
	assert_bool(camp.inside(at + step.normalized() * EnemyBrain.STEP_AHEAD)).is_false()
	# Round a corner: heading diagonally past it, it keeps going along the side it can.
	var corner := camp.point(Vector2(camp.half + 0.3, camp.half + 0.3))
	var past := camp.keep_out_step(corner, (-camp.right - camp.out * 0.2).normalized(), EnemyBrain.STEP_AHEAD)
	assert_bool(past.is_zero_approx()).is_false()
	# A step that never reaches the fence is left alone.
	var far := camp.point(Vector2(camp.half + 10.0, 0.0))
	assert_bool(camp.keep_out_step(far, -camp.right, EnemyBrain.STEP_AHEAD).is_equal_approx(-camp.right)).is_true()


func test_inside_it_may_walk_out_or_along_but_not_deeper() -> void:
	var camp := _camp(Vector3.ZERO)
	# Near the right-hand fence, inside.
	var at := camp.point(Vector2(camp.half - 1.0, 0.0))
	assert_bool(camp.keep_out_step(at, camp.right, EnemyBrain.STEP_AHEAD).is_equal_approx(camp.right)).is_true()
	assert_bool(camp.keep_out_step(at, camp.out, EnemyBrain.STEP_AHEAD).is_equal_approx(camp.out)).is_true()
	assert_bool(camp.keep_out_step(at, -camp.right, EnemyBrain.STEP_AHEAD).is_zero_approx()).is_true()
	var slanted := camp.keep_out_step(at, (-camp.right + camp.out).normalized(), EnemyBrain.STEP_AHEAD)
	assert_float(slanted.dot(camp.right)).is_equal_approx(0.0, 0.001)
	assert_float(slanted.dot(camp.out)).is_greater(0.5)
