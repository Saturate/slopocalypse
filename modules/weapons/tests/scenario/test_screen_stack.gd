extends GdUnitTestSuite
## Modding opened over the inventory: Esc closes modding first and leaves the inventory up
## with a free mouse; the next Esc closes the inventory and gives the mouse back to the
## game. Skipped when the inventory module is not there (it is deletable).

const PLAYER := "res://modules/player/scenes/player.tscn"
const WEAPONS := "res://modules/weapons/weapons_module.gd"
const INVENTORY := "res://modules/inventory/inventory_module.gd"

var _inventory_screen: Node
var _modding: ModdingScreen


func before_test() -> void:
	if not ResourceLoader.exists(INVENTORY):
		return
	var inventory: Node = auto_free((load(INVENTORY) as GDScript).new())
	add_child(inventory)
	var weapons: Node = auto_free((load(WEAPONS) as GDScript).new())
	add_child(weapons)
	var player: PlayerController = auto_free((load(PLAYER) as PackedScene).instantiate())
	player.set_meta(&"peer_id", 1)
	player.add_to_group(&"players")
	add_child(player)
	EventBus.publish(&"player.spawned", {"player": player, "local": false})
	_inventory_screen = auto_free((load("res://modules/inventory/scripts/inventory_screen.gd") as GDScript).new())
	_inventory_screen.set(&"inventory", inventory)
	_inventory_screen.set(&"peer", 1)
	add_child(_inventory_screen)
	_modding = auto_free(ModdingScreen.new())
	_modding.weapons = weapons
	_modding.player = player
	add_child(_modding)
	UiStack.set_captures_when_empty(true)


func after_test() -> void:
	UiStack.clear()


func _press_cancel() -> void:
	var ev := InputEventAction.new()
	ev.action = &"ui_cancel"
	ev.pressed = true
	get_viewport().push_input(ev)


func test_esc_closes_the_screen_on_top_first() -> void:
	if _inventory_screen == null:
		return
	_inventory_screen.call(&"open")
	_modding.open()
	assert_bool(UiStack.is_top(_modding)).is_true()
	_press_cancel()
	assert_bool(_modding.is_open()).is_false()
	assert_bool(_inventory_screen.call(&"is_open")).is_true()
	assert_int(UiStack.mouse_mode()).is_equal(Input.MOUSE_MODE_VISIBLE)
	_press_cancel()
	assert_bool(_inventory_screen.call(&"is_open")).is_false()
	assert_int(UiStack.mouse_mode()).is_equal(Input.MOUSE_MODE_CAPTURED)


func test_tab_does_not_close_the_inventory_under_modding() -> void:
	if _inventory_screen == null:
		return
	_inventory_screen.call(&"open")
	_modding.open()
	_inventory_screen.call(&"toggle")
	assert_bool(_inventory_screen.call(&"is_open")).is_true()
	assert_bool(UiStack.is_top(_modding)).is_true()
