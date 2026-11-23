extends GdUnitTestSuite
## A copy of someone else's body on a client must not run its own movement: it only shows
## what the server sends. Godot switches physics processing on at `ready` for any script with
## `_physics_process`, so switching it off before the node is added does not hold.

const PLAYER := "res://modules/player/scenes/player.tscn"


func test_a_client_copy_stays_still_after_it_is_added() -> void:
	var copy: PlayerController = auto_free((load(PLAYER) as PackedScene).instantiate())
	PlayerController.hold_still(copy)
	add_child(copy)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_bool(copy.is_physics_processing()).is_false()


func test_a_copy_held_still_takes_its_eye_height_from_the_synced_crouch() -> void:
	var copy: PlayerController = auto_free((load(PLAYER) as PackedScene).instantiate())
	PlayerController.hold_still(copy)
	add_child(copy)
	await get_tree().physics_frame
	var head := copy.get_node("Head") as Node3D
	var standing := head.position.y
	copy.intent().crouch = true
	await get_tree().process_frame
	await get_tree().process_frame
	assert_float(head.position.y).is_less(standing - 0.4)


func test_a_copy_held_still_is_grounded_by_its_synced_velocity() -> void:
	var copy: PlayerController = auto_free((load(PLAYER) as PackedScene).instantiate())
	PlayerController.hold_still(copy)
	add_child(copy)
	await get_tree().physics_frame
	copy.velocity = Vector3(6.0, 0.0, 0.0)
	assert_bool(copy.grounded()).is_true()
	copy.velocity = Vector3(0.0, -6.0, 0.0)
	assert_bool(copy.grounded()).is_false()


func test_a_copy_held_still_leans_with_the_synced_lean_and_comes_back_upright() -> void:
	var copy: PlayerController = auto_free((load(PLAYER) as PackedScene).instantiate())
	PlayerController.hold_still(copy)
	add_child(copy)
	await get_tree().physics_frame
	var head := copy.get_node("Head") as Node3D
	copy.intent().lean = 1
	for i in 30:
		await get_tree().process_frame
	assert_float(copy.lean_amount()).is_equal(1.0)
	assert_float(head.rotation.z).is_less(-0.1)
	copy.intent().lean = 0
	for i in 30:
		await get_tree().process_frame
	assert_float(copy.lean_amount()).is_equal(0.0)
	assert_float(head.position.x).is_equal(0.0)
	assert_float(head.rotation.z).is_equal(0.0)
