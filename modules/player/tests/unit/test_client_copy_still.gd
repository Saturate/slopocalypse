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
