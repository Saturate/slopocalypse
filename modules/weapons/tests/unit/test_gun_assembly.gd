extends GdUnitTestSuite
## Guns are assembled from parts in data: Rust checks the build and computes stats,
## GunAssembly puts the part meshes on their mount points with the markers ADS and shot
## effects use.


func test_the_default_build_is_a_working_gun() -> void:
	var result := GunAssembly.assemble_named(GunAssembly.default_build())
	assert_bool(result["ok"]).override_failure_message(str(result["errors"])).is_true()
	var stats: Dictionary = result["stats"]
	assert_float(stats["magazine"]).is_equal(30.0)
	assert_float(stats["damage"]).is_greater(0.0)
	assert_float(stats["ads_zoom"]).is_equal(1.25)


func test_every_listed_build_assembles() -> void:
	for build: String in GunAssembly.build_names():
		var result := GunAssembly.assemble_named(build)
		assert_bool(result["ok"]).override_failure_message("%s: %s" % [build, result["errors"]]).is_true()


func test_parts_change_the_numbers() -> void:
	var standard: Dictionary = GunAssembly.assemble_named("ar_standard")["stats"]
	var heavy: Dictionary = GunAssembly.assemble_named("ar_heavy")["stats"]
	var cqb: Dictionary = GunAssembly.assemble_named("ar_cqb")["stats"]
	assert_float(heavy["magazine"]).is_equal(45.0)
	assert_float(heavy["ads_seconds"]).is_greater(standard["ads_seconds"])
	assert_float(cqb["range"]).is_less(standard["range"])
	assert_float(cqb["ads_seconds"]).is_less(standard["ads_seconds"])


func test_a_broken_build_says_why() -> void:
	var parts := GunAssembly.catalogue()
	var result := WeaponBuild.assemble(parts, {"receiver": "rcv_ar", "stock": "mag_ar_30"})
	assert_bool(result["ok"]).is_false()
	var errors := str(result["errors"])
	assert_str(errors).contains("stock")
	assert_str(errors).contains("barrel")


func test_the_model_puts_every_part_on_its_mount() -> void:
	var build: Dictionary = GunAssembly.build("ar_standard")
	var model: Node3D = auto_free(GunAssembly.build_model(build))
	add_child(model)
	for slot: String in build:
		var part := model.find_child(slot, true, false) as MeshInstance3D
		assert_object(part).override_failure_message("no mesh for " + slot).is_not_null()
		assert_object(part.mesh).is_not_null()
	# The barrel hangs off the receiver's barrel mount; the muzzle off the barrel's end.
	var muzzle_part := model.find_child("muzzle", true, false) as Node3D
	assert_float(muzzle_part.global_position.z).is_less(-0.5)


func test_markers_come_from_the_outermost_part() -> void:
	var model: Node3D = auto_free(GunAssembly.build_model(GunAssembly.build("ar_heavy")))
	add_child(model)
	var muzzles := model.find_children("Muzzle", "Marker3D", true, false)
	assert_int(muzzles.size()).is_equal(1)
	# The suppressor's end, beyond where the bare barrel would end.
	assert_float((muzzles[0] as Node3D).global_position.z).is_less(-0.75)
	assert_int(model.find_children("Sight", "Marker3D", true, false).size()).is_equal(1)
