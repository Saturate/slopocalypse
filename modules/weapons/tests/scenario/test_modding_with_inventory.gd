extends GdUnitTestSuite
## With the inventory module loaded, a build change takes the fitted parts from the
## player's inventory and puts the removed ones back; parts they do not own, or no room for
## what comes off, refuse the change and leave everything as it was. Skipped when the
## inventory module is not there (it is deletable).

const PLAYER := "res://modules/player/scenes/player.tscn"
const WEAPONS := "res://modules/weapons/weapons_module.gd"
const INVENTORY := "res://modules/inventory/inventory_module.gd"

var _weapons: Node
var _inventory: Node


func before_test() -> void:
	if not ResourceLoader.exists(INVENTORY):
		return
	_inventory = auto_free((load(INVENTORY) as GDScript).new())
	add_child(_inventory)
	_weapons = auto_free((load(WEAPONS) as GDScript).new())
	add_child(_weapons)


func _spawn(peer: int) -> PlayerController:
	var player: PlayerController = auto_free((load(PLAYER) as PackedScene).instantiate())
	player.set_meta(&"peer_id", peer)
	player.add_to_group(&"players")
	add_child(player)
	EventBus.publish(&"player.spawned", {"player": player, "local": false})
	return player


func test_fitting_a_scope_takes_it_from_the_bag_and_returns_the_red_dot() -> void:
	if _inventory == null:
		return
	_spawn(31)
	assert_int(_inventory.call(&"count", 31, "opt_scope_4x")).is_equal(1)
	var build: Dictionary = _weapons.call(&"build_of", 31, "primary")
	build = GunModding.with_part(build, "optic", "opt_scope_4x")
	assert_bool(_weapons.call(&"server_set_build", 31, build)).is_true()
	assert_int(_inventory.call(&"count", 31, "opt_scope_4x")).is_equal(0)
	assert_int(_inventory.call(&"count", 31, "opt_reddot")).is_equal(1)


func test_a_part_you_do_not_own_is_refused() -> void:
	if _inventory == null:
		return
	_spawn(32)
	_inventory.call(&"server_take", 32, "opt_holo")
	var build: Dictionary = GunModding.with_part(_weapons.call(&"build_of", 32, "primary"), "optic", "opt_holo")
	Log.begin_capture()
	var ok: bool = _weapons.call(&"server_set_build", 32, build)
	var entries := Log.end_capture()
	assert_bool(ok).is_false()
	assert_str(LogCapture.text(entries)).contains("does not own")
	assert_str(_weapons.call(&"build_of", 32, "primary")["optic"]).is_equal("opt_reddot")


func test_no_room_for_what_comes_off_refuses_and_changes_nothing() -> void:
	if _inventory == null:
		return
	_spawn(33)
	while _inventory.call(&"server_give", 33, "mag_pistol_15"):
		pass
	var before := _inventory.call(&"count", 33, "opt_scope_4x") as int
	# Taking the scope out frees 3 cells, but the barrel coming off needs 4 in a row.
	var build: Dictionary = _weapons.call(&"build_of", 33, "primary")
	build = GunModding.with_part(build, "optic", "opt_scope_4x")
	build = GunModding.with_part(build, "barrel", "bar_ar_10")
	build["muzzle"] = "muz_flash"
	Log.begin_capture()
	var ok: bool = _weapons.call(&"server_set_build", 33, build)
	Log.end_capture()
	assert_bool(ok).is_false()
	assert_int(_inventory.call(&"count", 33, "opt_scope_4x")).is_equal(before)
	assert_int(_inventory.call(&"count", 33, "bar_ar_10")).is_equal(1)
	assert_int(_inventory.call(&"count", 33, "bar_ar_14")).is_equal(0)


func test_part_changes_list_what_goes_on_and_comes_off() -> void:
	var changes: Dictionary = (load(WEAPONS) as GDScript).call(&"part_changes", {"optic": "a", "muzzle": "m"}, {"optic": "b", "stock": "s"})
	assert_array(changes["fitted"]).contains_exactly_in_any_order(["b", "s"])
	assert_array(changes["removed"]).contains_exactly_in_any_order(["a", "m"])
