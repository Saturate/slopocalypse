extends GdUnitTestSuite
## Changing a player's gun: the server checks the build with the Rust rules, then everyone
## re-equips that player; players who spawn later get it too.

const PLAYER := "res://modules/player/scenes/player.tscn"
const MODULE := "res://modules/weapons/weapons_module.gd"

var _module: Node


func before_test() -> void:
	_module = auto_free((load(MODULE) as GDScript).new())
	add_child(_module)


func _spawn(peer: int) -> PlayerController:
	var player: PlayerController = auto_free((load(PLAYER) as PackedScene).instantiate())
	player.set_meta(&"peer_id", peer)
	player.add_to_group(&"players")
	add_child(player)
	EventBus.publish(&"player.spawned", {"player": player, "local": false})
	return player


func _carried(player: PlayerController) -> HitscanWeapon:
	return player.get_node("Head/Camera/Weapon_primary") as HitscanWeapon


func test_a_valid_build_re_equips_the_player() -> void:
	var player := _spawn(7)
	var build := GunAssembly.build("ar_heavy")
	assert_bool(_module.call(&"server_set_build", 7, build)).is_true()
	await get_tree().process_frame
	assert_float(float(_carried(player).stats["magazine"])).is_equal(45.0)
	var held := ShotEffects.held_rifle(player)
	assert_object(held.get_node_or_null("muzzle")).is_not_null()
	assert_int(player.get_node("Head/Camera").get_children().filter(func(c: Node) -> bool: return c is HitscanWeapon and not c.is_queued_for_deletion()).size()).is_equal(2)
	# The swap empties the magazine; the new gun is reloading.
	assert_bool(_carried(player).rules.is_reloading()).is_true()


func test_a_broken_build_is_refused_and_changes_nothing() -> void:
	var player := _spawn(8)
	var before := _carried(player)
	Log.begin_capture()
	var ok: bool = _module.call(&"server_set_build", 8, {"receiver": "rcv_ar", "optic": "opt_scope_4x"})
	var entries := Log.end_capture()
	assert_bool(ok).is_false()
	assert_str(LogCapture.text(entries)).contains("refused")
	assert_object(_carried(player)).is_same(before)


func test_only_strings_get_through() -> void:
	Log.begin_capture()
	var ok: bool = _module.call(&"server_set_build", 9, {"receiver": 5, 3: "bar_ar_14"})
	Log.end_capture()
	assert_bool(ok).is_false()


func test_a_player_spawned_later_gets_their_build() -> void:
	_module.call(&"server_set_build", 11, GunAssembly.build("ar_cqb"))
	var player := _spawn(11)
	var held := ShotEffects.held_rifle(player)
	var stock := held.get_node("stock") as MeshInstance3D
	assert_object(stock.mesh).is_same(GunPartMeshes.mesh("stock_light"))


func test_everyone_carries_a_rifle_and_a_pistol_and_1_2_switch() -> void:
	var player := _spawn(12)
	var camera := player.get_node("Head/Camera")
	var rifle := camera.get_node("Weapon_primary") as HitscanWeapon
	var pistol := camera.get_node("Weapon_secondary") as HitscanWeapon
	assert_bool(rifle.active).is_true()
	assert_bool(pistol.active).is_false()
	assert_bool(pistol.semi_auto).is_true()
	player.intent().weapon_2 = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_int(player.intent().weapon_slot).is_equal(1)
	assert_bool(pistol.active).is_true()
	assert_bool(rifle.active).is_false()
	var held := ShotEffects.held_rifle(player)
	assert_object((held.get_node("receiver") as MeshInstance3D).mesh).is_same(GunPartMeshes.mesh("pistol_frame"))
	player.intent().weapon_1 = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_bool(rifle.active).is_true()


func test_a_pistol_build_goes_in_the_secondary_slot() -> void:
	var player := _spawn(13)
	assert_bool(_module.call(&"server_set_build", 13, GunAssembly.build("pistol_tactical"))).is_true()
	await get_tree().process_frame
	var pistol := player.get_node("Head/Camera/Weapon_secondary") as HitscanWeapon
	assert_float(float(pistol.stats["magazine"])).is_equal(21.0)
	assert_str(_module.call(&"build_of", 13, "primary")["receiver"]).is_equal("rcv_ar")
