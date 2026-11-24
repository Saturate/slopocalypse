extends GdUnitTestSuite
## The modding screen's rules: what fits where, what a swap does to the rest of the gun,
## and how two builds compare.


func test_a_slot_offers_only_parts_that_fit_it() -> void:
	var optics := GunModding.options("optic")
	assert_array(optics).contains(["opt_reddot", "opt_holo", "opt_scope_4x"])
	for id in optics:
		assert_str(GunAssembly.catalogue()[id]["slot"]).is_equal("optic")


func test_the_muzzle_slot_exists_only_with_a_barrel() -> void:
	var build := GunAssembly.build("ar_standard")
	assert_bool(GunModding.is_available("muzzle", build)).is_true()
	var no_barrel := build.duplicate()
	no_barrel.erase("barrel")
	assert_bool(GunModding.is_available("muzzle", no_barrel)).is_false()


func test_removing_a_barrel_takes_its_muzzle_device_with_it() -> void:
	var build := GunModding.with_part(GunAssembly.build("ar_standard"), "barrel", "")
	assert_bool(build.has("barrel")).is_false()
	assert_bool(build.has("muzzle")).is_false()
	assert_bool(build.has("optic")).is_true()


func test_swapping_a_part_keeps_the_rest() -> void:
	var before := GunAssembly.build("ar_standard")
	var after := GunModding.with_part(before, "optic", "opt_scope_4x")
	assert_str(after["optic"]).is_equal("opt_scope_4x")
	assert_str(after["barrel"]).is_equal(before["barrel"])
	assert_str(before["optic"]).is_equal("opt_reddot")


func test_comparing_marks_better_and_worse() -> void:
	var standard: Dictionary = GunAssembly.assemble_named("ar_standard")["stats"]
	var heavy: Dictionary = GunAssembly.assemble_named("ar_heavy")["stats"]
	var rows := GunModding.compare(standard, heavy)
	var by_key := {}
	for row in rows:
		by_key[row["key"]] = row
	# More rounds is better, a slower aim is worse, the same damage is neither.
	assert_int(by_key["magazine"]["verdict"]).is_equal(1)
	assert_int(by_key["ads_seconds"]["verdict"]).is_equal(-1)
	assert_int(by_key["damage"]["verdict"]).is_equal(0)
	assert_str(by_key["magazine"]["delta"]).is_equal("+15")
	assert_str(by_key["damage"]["delta"]).is_empty()


func test_the_bolt_cycle_shows_only_for_a_gun_that_has_one() -> void:
	var rifle: Dictionary = GunAssembly.assemble_named("ar_standard")["stats"]
	var bolt: Dictionary = GunAssembly.assemble_named("bolt_standard")["stats"]
	var keys := GunModding.compare(rifle, rifle).map(func(row: Dictionary) -> String: return row["key"])
	assert_bool(keys.has("cycle_seconds")).is_false()
	keys = GunModding.compare(bolt, bolt).map(func(row: Dictionary) -> String: return row["key"])
	assert_bool(keys.has("cycle_seconds")).is_true()


func test_a_bolt_action_takes_only_its_own_parts_and_shares_the_optic_rail() -> void:
	var slots := GunModding.slots_for(GunAssembly.build("bolt_standard"))
	for slot in ["bolt_barrel", "bolt_stock", "bolt_handle", "bolt_magazine", "optic"]:
		assert_bool(slots.has(slot)).override_failure_message(slot).is_true()
	assert_bool(slots.has("magazine")).is_false()
	assert_bool(GunModding.options("optic").has("opt_scope_8x")).is_true()


func test_a_bolt_actions_fire_rate_is_what_the_bolt_allows() -> void:
	var bolt: Dictionary = GunAssembly.assemble_named("bolt_standard")["stats"]
	var shown := GunModding.shown_value(bolt, "rounds_per_minute")
	assert_float(shown).is_equal_approx(60.0 / float(bolt["cycle_seconds"]), 0.01)
	var rifle: Dictionary = GunAssembly.assemble_named("ar_standard")["stats"]
	assert_float(GunModding.shown_value(rifle, "rounds_per_minute")).is_equal(float(rifle["rounds_per_minute"]))


func _labels(rows: Array[Dictionary]) -> Array:
	return rows.map(func(r: Dictionary) -> String: return str(r["label"]))


func test_a_gun_lists_its_damage_fire_rate_and_magazine() -> void:
	var rows := GunModding.gun_detail_rows(GunAssembly.build("ar_standard"))
	assert_array(_labels(rows)).contains(["Damage", "Fire rate", "Magazine"])
	assert_str(str(rows[0]["value"])).is_equal("25")


func test_a_launcher_lists_its_rocket_damage() -> void:
	var rows := GunModding.gun_detail_rows(GunAssembly.build("launcher"))
	var damage := rows.filter(func(r: Dictionary) -> bool: return str(r["label"]) == "Damage")
	assert_int(damage.size()).is_equal(1)
	assert_str(str(damage[0]["value"])).is_equal("%.0f" % float(RocketLauncher.rocket_config()["damage"]))


func test_a_part_lists_what_it_changes() -> void:
	var rows := GunModding.part_detail_rows(GunAssembly.catalogue()["stk_ar_std"]["stats"])
	assert_array(_labels(rows)).contains(["Recoil", "Ergonomics", "Weight"])
	assert_array(_labels(rows)).not_contains(["Magazine"])
	assert_str(str(rows[0]["value"])).is_equal("-25%")
