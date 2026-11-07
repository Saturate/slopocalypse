extends GdUnitTestSuite
## The enemy's geometry: which way to look, what it can see, how its aim settles.


func test_look_angles_point_at_the_target() -> void:
	var ahead := EnemyBrain.look_angles(Vector3.ZERO, Vector3(0, 0, -10))
	assert_float(ahead.x).is_equal_approx(0.0, 0.001)
	assert_float(ahead.y).is_equal_approx(0.0, 0.001)
	# To the right (+X) is a quarter turn clockwise seen from above: negative yaw.
	assert_float(EnemyBrain.look_angles(Vector3.ZERO, Vector3(10, 0, 0)).x).is_equal_approx(-PI / 2.0, 0.001)
	assert_float(EnemyBrain.look_angles(Vector3.ZERO, Vector3(0, 10, -10)).y).is_equal_approx(PI / 4.0, 0.001)


func test_the_sight_cone_sees_ahead_not_behind() -> void:
	assert_bool(EnemyBrain.in_cone(Vector3.ZERO, 0.0, Vector3(3, 0, -10), 120.0)).is_true()
	assert_bool(EnemyBrain.in_cone(Vector3.ZERO, 0.0, Vector3(0, 0, 10), 120.0)).is_false()
	assert_bool(EnemyBrain.in_cone(Vector3.ZERO, PI, Vector3(0, 0, 10), 120.0)).is_true()


func test_aim_starts_wide_and_settles() -> void:
	assert_float(EnemyBrain.aim_error(0.0, 5.0, 1.0, 2.0)).is_equal(5.0)
	assert_float(EnemyBrain.aim_error(1.0, 5.0, 1.0, 2.0)).is_equal(3.0)
	assert_float(EnemyBrain.aim_error(10.0, 5.0, 1.0, 2.0)).is_equal(1.0)
