extends GdUnitTestSuite
## Every one-shot action either has a key in player.json or comes from a menu button; the
## input code polls only the bound ones, so a menu-only action never asks for a missing key.

const CONFIG := "res://modules/player/data/player.json"


func test_one_shots_have_keys_unless_a_menu_sends_them() -> void:
	var bindings: Dictionary = Data.load_json(CONFIG)["bindings"]
	for action: StringName in PlayerIntent.ONE_SHOTS:
		var key_name := "charge" if action == &"throw" else String(action)
		var bound := bindings.has(key_name)
		var from_menu := action in PlayerInput.FROM_MENU
		assert_bool(bound != from_menu).override_failure_message("%s: bound %s, from a menu %s" % [action, bound, from_menu]).is_true()
