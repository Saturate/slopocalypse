extends GdUnitTestSuite
## A client's frozen car moves its wheels from what it is seen to do: hubs on the ground
## within the spring travel, front wheels turned by how sharply it turns, nothing read from a
## car standing still.

const LOOKS := "res://modules/car/scripts/car_looks.gd"


func _call(method: StringName, args: Array) -> Variant:
	return (load(LOOKS) as GDScript).callv(method, args)


func test_a_wheel_sits_on_the_ground_within_its_spring() -> void:
	# Ground 0.6 m under the mount: radius 0.38 leaves the hub 0.22 m down.
	assert_float(float(_call(&"hub_drop", [0.6, 0.38, 0.3, 0.25]))).is_equal_approx(0.22, 0.001)
	# Over a bump it can only come up so far, and over a hole it hangs at full travel.
	assert_float(float(_call(&"hub_drop", [0.2, 0.38, 0.3, 0.25]))).is_equal_approx(0.05, 0.001)
	assert_float(float(_call(&"hub_drop", [INF, 0.38, 0.3, 0.25]))).is_equal_approx(0.55, 0.001)


func test_the_front_wheels_turn_with_the_turn() -> void:
	var max_steer := deg_to_rad(30.0)
	var left := float(_call(&"steer_for", [10.0, 0.5, 2.7, max_steer]))
	assert_float(left).is_greater(0.0)
	assert_float(left).is_equal_approx(atan(2.7 * 0.5 / 10.0), 0.001)
	# Reversing through the same turn steers the other way; a hard turn stops at full lock.
	assert_float(float(_call(&"steer_for", [-10.0, 0.5, 2.7, max_steer]))).is_less(0.0)
	assert_float(float(_call(&"steer_for", [2.0, 3.0, 2.7, max_steer]))).is_equal_approx(max_steer, 0.001)
	assert_float(float(_call(&"steer_for", [0.1, 0.5, 2.7, max_steer]))).is_equal(0.0)


func test_a_turn_is_measured_about_the_cars_up() -> void:
	var quarter := float(_call(&"signed_turn", [Vector3.BACK, Vector3.RIGHT, Vector3.UP]))
	assert_float(absf(quarter)).is_equal_approx(PI / 2.0, 0.001)
	assert_float(float(_call(&"signed_turn", [Vector3.BACK, Vector3.BACK, Vector3.UP]))).is_equal_approx(0.0, 0.001)
