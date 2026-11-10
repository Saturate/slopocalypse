extends GdUnitTestSuite
## Medkits heal over a few seconds and are used up; crates open for looting, hand over what
## fits and refill.

const PLAYER := "res://modules/player/scenes/player.tscn"
const MODULE := "res://modules/inventory/inventory_module.gd"

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


func test_a_medkit_heals_over_time_and_is_used_up() -> void:
	var player := _spawn(51)
	var health := player.get_node("Health") as HealthComponent
	health.server_apply_damage(70.0)
	var kits: int = _module.call(&"count", 51, "medkit")
	assert_int(kits).is_greater(0)
	assert_bool(_module.call(&"server_use", 51, "medkit")).is_true()
	assert_int(_module.call(&"count", 51, "medkit")).is_equal(kits - 1)
	# Not all at once.
	await get_tree().physics_frame
	assert_float(health.health).is_less(health.max_health - 30.0)
	for i in 240:
		await get_tree().physics_frame
	assert_float(health.health).is_equal_approx(90.0, 0.5)


func test_no_medkit_wasted_at_full_health() -> void:
	_spawn(52)
	var kits: int = _module.call(&"count", 52, "medkit")
	assert_bool(_module.call(&"server_use", 52, "medkit")).is_false()
	assert_int(_module.call(&"count", 52, "medkit")).is_equal(kits)


func test_searching_a_crate_takes_what_fits_and_it_refills() -> void:
	var player := _spawn(53)
	var crate: LootCrate = _module.call(&"server_spawn_crate", player.global_position + Vector3(0, 0, -1.5))
	await get_tree().process_frame
	var inside: Array = (_module.call(&"crate_contents", crate) as Array).duplicate()
	assert_int(inside.size()).is_greater(0)
	var payload := {"player": player}
	EventBus.publish(&"player.interact", payload)
	assert_bool(payload.get("handled", false)).is_true()
	_module.call(&"server_take_all", 53)
	assert_int((_module.call(&"crate_contents", crate) as Array).size()).is_equal(0)
	assert_bool(crate.get_meta(&"empty", false)).is_true()
	for item: String in inside:
		assert_int(_module.call(&"count", 53, item)).is_greater(0)
