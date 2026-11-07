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
