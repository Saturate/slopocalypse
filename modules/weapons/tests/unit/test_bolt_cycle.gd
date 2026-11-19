extends GdUnitTestSuite
## The bolt being worked on a held bolt-action: the right hand's grip point goes to the bolt
## knob while the bolt turns up and slides back, and everything is back at rest after.


func _gun() -> Node3D:
	var gun: Node3D = auto_free(GunAssembly.build_model(GunAssembly.build("bolt_standard")))
	add_child(gun)
	return gun


func test_mid_cycle_the_hand_is_on_the_knob_and_the_bolt_is_back() -> void:
	var gun := _gun()
	var bolt := gun.get_node("bolt_handle") as Node3D
	var rest_bolt := bolt.position
	var knob_rest := (gun.get_node("BoltKnob") as Node3D).position
	var cycle := BoltCycle.start(gun, 1.0)
	cycle.pose(0.56)
	var grip := (gun.get_node("GripR") as Node3D).position
	var knob_now := bolt.transform * (Transform3D(Basis.IDENTITY, rest_bolt).affine_inverse() * knob_rest)
	assert_float(grip.distance_to(knob_now)).is_less(0.005)
	# Slid back toward the shooter (+Z) with the handle turned up.
	assert_float(bolt.position.z).is_greater(rest_bolt.z + 0.05)
	assert_float(knob_now.y).is_greater(knob_rest.y + 0.02)


func test_after_the_cycle_everything_is_at_rest() -> void:
	var gun := _gun()
	var grip_rest := (gun.get_node("GripR") as Node3D).position
	var bolt_rest := (gun.get_node("bolt_handle") as Node3D).transform
	var cycle := BoltCycle.start(gun, 1.0)
	cycle.pose(0.5)
	cycle.finish()
	assert_vector((gun.get_node("GripR") as Node3D).position).is_equal(grip_rest)
	assert_bool((gun.get_node("bolt_handle") as Node3D).transform.is_equal_approx(bolt_rest)).is_true()


func test_a_gun_without_a_bolt_part_has_nothing_to_work() -> void:
	var gun: Node3D = auto_free(GunAssembly.build_model(GunAssembly.build("ar_standard")))
	assert_object(BoltCycle.start(gun, 1.0)).is_null()
