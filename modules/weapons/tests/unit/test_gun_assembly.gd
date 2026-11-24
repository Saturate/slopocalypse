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


func test_every_build_has_the_detail_budget_the_spec_asks() -> void:
	# The spec's budget for one assembled gun: detailed enough to read rails and slots up
	# close, cheap enough for four players and their kit.
	for name: String in GunAssembly.build_names():
		var total := 0
		for slot: String in GunAssembly.build(name):
			var part: Dictionary = GunAssembly.catalogue()[GunAssembly.build(name)[slot]]
			total += GunPartMeshes.triangles(GunPartMeshes.mesh(part["mesh"]))
		# Pistols are a third the size of a rifle and get a smaller share.
		var low := 2000 if GunAssembly.weapon_slot_of(GunAssembly.build(name)) == "primary" else 500
		assert_int(total).override_failure_message("%s has %d triangles" % [name, total]).is_between(low, 6000)


func test_optics_have_glass_to_look_through() -> void:
	for id in ["optic_reddot", "optic_holo"]:
		var m := GunPartMeshes.mesh(id)
		var see_through := false
		for s in m.get_surface_count():
			var mat := m.surface_get_material(s) as BaseMaterial3D
			see_through = see_through or mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
		assert_bool(see_through).override_failure_message(id).is_true()


func test_a_scope_magnifies_and_brings_the_eye_closer() -> void:
	var stats: Dictionary = GunAssembly.assemble_named("ar_dmr")["stats"]
	assert_float(stats["magnification"]).is_equal(4.0)
	assert_float(GunAssembly.assemble_named("ar_standard")["stats"]["magnification"]).is_equal(1.0)
	var model: Node3D = auto_free(GunAssembly.build_model(GunAssembly.build("ar_dmr")))
	var sight := model.get_node("Sight") as Node3D
	assert_float(float(sight.get_meta(&"eye_relief", 0.0))).is_equal(0.06)



func test_the_scope_picture_comes_up_only_near_the_eye() -> void:
	assert_float(ScopeView.shown_for(0.3)).is_equal(0.0)
	assert_float(ScopeView.shown_for(1.0)).is_equal(1.0)


func test_the_carried_build_is_the_default_unless_overridden() -> void:
	assert_str(GunAssembly.chosen_build()).is_equal(GunAssembly.default_build())
	GunAssembly.override_build = "ar_cqb"
	assert_str(GunAssembly.chosen_build()).is_equal("ar_cqb")
	GunAssembly.override_build = ""


func test_the_bolt_action_is_a_manual_action_with_a_magnified_scope() -> void:
	var slots := GunAssembly.build("bolt_standard")
	var stats: Dictionary = GunAssembly.assemble_named("bolt_standard")["stats"]
	var rifle: Dictionary = GunAssembly.assemble_named("ar_standard")["stats"]
	assert_float(stats["magazine"]).is_equal(5.0)
	assert_float(GunAssembly.cycle_seconds_of(slots, stats)).is_greater(0.0)
	assert_float(GunAssembly.cycle_seconds_of(GunAssembly.build("ar_standard"), rifle)).is_equal(0.0)
	assert_float(stats["damage"]).is_greater(float(rifle["damage"]) * 2.0)
	# Accurate only aimed: its hip spread is wide, its receiver makes aiming tighten it.
	assert_float(float(GunAssembly.receiver_of(slots).get("ads_spread_multiplier", 1.0))).is_less(0.05)
	# The long scope magnifies more than any other optic.
	for id: String in GunModding.options("optic"):
		if id != "opt_scope_8x":
			assert_float(float(GunAssembly.catalogue()[id]["stats"].get("magnification", 1.0))).is_less(float(stats["magnification"]))


func test_every_manual_receiver_says_how_long_its_cycle_is() -> void:
	for id: String in GunAssembly.catalogue():
		var part: Dictionary = GunAssembly.catalogue()[id]
		if str(part.get("action", "")) == "manual":
			assert_float(float((part["stats"] as Dictionary).get("cycle_seconds", 0.0))).override_failure_message(id).is_greater(0.0)


func test_the_voxel_parts_hang_where_the_receiver_mounts_them() -> void:
	# The voxel kit draws the rifle whole, then cuts each part out around its mount; the
	# receiver's mounts in the data must be the same points.
	var receiver: Dictionary = GunAssembly.catalogue()["rcv_bolt"]
	var mounts: Dictionary = receiver["mounts"]
	var by_slot := {"bolt_barrel": "barrel", "bolt_stock": "stock", "bolt_handle": "bolt", "bolt_magazine": "magazine", "optic": "scope"}
	for slot: String in by_slot:
		var a: Array = mounts[slot]
		assert_vector(Vector3(a[0], a[1], a[2])).override_failure_message(slot).is_equal_approx(VoxBoltRifle.MOUNTS[by_slot[slot]], Vector3.ONE * 0.0001)
	var knob: Array = GunAssembly.catalogue()["bolt_std"]["markers"]["BoltKnob"]
	assert_vector(Vector3(knob[0], knob[1], knob[2])).is_equal_approx(VoxBoltRifle.knob(), Vector3.ONE * 0.0001)
	var scope_sight: Array = GunAssembly.catalogue()["opt_scope_8x"]["markers"]["Sight"]
	assert_vector(Vector3(scope_sight[0], scope_sight[1], scope_sight[2])).is_equal_approx(Vector3(0.0, VoxBoltRifle.SCOPE_AXIS, VoxBoltRifle.SCOPE_EYEPIECE_Z), Vector3.ONE * 0.0001)


func test_the_bolt_actions_parts_are_voxel_meshes_in_their_own_space() -> void:
	var barrel := GunPartMeshes.mesh("vox_bolt_barrel")
	assert_object(barrel).is_not_null()
	var box := barrel.get_aabb()
	# From the mount forward to the muzzle, round the bore.
	assert_float(box.position.z).is_equal_approx(-VoxBoltRifle.BARREL_LENGTH, 0.01)
	# Its rounded back end tucks a little into the receiver.
	assert_float(box.end.z).is_less(0.02)
	assert_float(box.get_center().y).is_equal_approx(0.0, 0.01)
	var model: Node3D = auto_free(GunAssembly.build_model(GunAssembly.build("bolt_standard")))
	add_child(model)
	assert_float((model.get_node("Muzzle") as Node3D).position.z).is_less(-0.7)
	for name: String in ["GripR", "GripL", "Sight", "BoltKnob"]:
		assert_object(model.get_node_or_null(name)).override_failure_message(name).is_not_null()


func test_the_machine_gun_is_a_heavy_belt_fed_automatic() -> void:
	var slots := GunAssembly.build("mg_standard")
	var result := GunAssembly.assemble_named("mg_standard")
	assert_bool(result["ok"]).override_failure_message(str(result["errors"])).is_true()
	var stats: Dictionary = result["stats"]
	var rifle: Dictionary = GunAssembly.assemble_named("ar_standard")["stats"]
	var receiver := GunAssembly.receiver_of(slots)
	var feel: Dictionary = Data.load_json(HitscanWeapon.CONFIG)["rifle"]
	# Fully automatic at about 900 rounds a minute from a 100-round belt.
	assert_str(str(receiver.get("fire_mode", "auto"))).is_equal("auto")
	assert_float(GunAssembly.cycle_seconds_of(slots, stats)).is_equal(0.0)
	assert_float(stats["rounds_per_minute"]).is_between(850.0, 950.0)
	assert_float(stats["magazine"]).is_equal(100.0)
	# Hits harder than the rifle, reloads, draws and aims far slower.
	assert_float(stats["damage"]).is_between(30.0, 35.0)
	assert_float(stats["damage"]).is_greater(float(rifle["damage"]))
	assert_float(stats["reload_seconds"]).is_between(5.0, 7.0)
	assert_float(stats["ads_seconds"]).is_greater(float(rifle["ads_seconds"]) * 2.0)
	assert_float(float(receiver["draw_seconds"])).is_greater(float(feel["draw_seconds"]) * 2.0)
	# Wide from the hip, tight on the bipod; heavy enough to slow whoever has it out.
	assert_float(stats["spread_degrees"]).is_greater(float(rifle["spread_degrees"]) * 2.0)
	assert_float(float(receiver["braced_spread_multiplier"])).is_less(0.5)
	assert_float(float(receiver["move_speed_multiplier"])).is_between(0.6, 0.95)
	assert_float(stats["weight"]).is_greater(float(rifle["weight"]) * 2.0)


func test_only_the_machine_gun_braces_or_slows() -> void:
	var feel: Dictionary = Data.load_json(HitscanWeapon.CONFIG)["rifle"]
	assert_float(float(feel["braced_spread_multiplier"])).is_equal(1.0)
	assert_float(float(feel["move_speed_multiplier"])).is_equal(1.0)


func test_the_machine_guns_voxel_parts_hang_where_the_receiver_mounts_them() -> void:
	var receiver: Dictionary = GunAssembly.catalogue()["rcv_mg"]
	var mounts: Dictionary = receiver["mounts"]
	var by_slot := {"heavy_barrel": "barrel", "heavy_stock": "stock", "bipod": "bipod", "belt_box": "belt"}
	for slot: String in by_slot:
		var a: Array = mounts[slot]
		assert_vector(Vector3(a[0], a[1], a[2])).override_failure_message(slot).is_equal_approx(VoxMachineGun.MOUNTS[by_slot[slot]], Vector3.ONE * 0.0001)
	# The hands go where the model has a grip and a handle.
	var grip: Array = receiver["markers"]["GripR"]
	assert_vector(Vector3(grip[0], grip[1], grip[2])).is_equal_approx(VoxMachineGun.GRIP, Vector3.ONE * 0.0001)
	var handle: Array = GunAssembly.catalogue()["bar_mg_heavy"]["markers"]["GripL"]
	assert_vector(Vector3(handle[0], handle[1], handle[2]) + VoxMachineGun.MOUNTS["barrel"]).is_equal_approx(VoxMachineGun.HANDLE, Vector3.ONE * 0.0001)
	var sight: Array = receiver["markers"]["Sight"]
	assert_float(float(sight[1])).is_equal_approx(VoxMachineGun.SIGHT_LINE, 0.0001)
	var model: Node3D = auto_free(GunAssembly.build_model(GunAssembly.build("mg_standard")))
	add_child(model)
	assert_float((model.get_node("Muzzle") as Node3D).position.z).is_equal_approx(-0.17 - VoxMachineGun.BARREL_LENGTH, 0.001)
	for name: String in ["GripR", "GripL", "Sight", "Muzzle"]:
		assert_object(model.get_node_or_null(name)).override_failure_message(name).is_not_null()
	for slot: String in GunAssembly.build("mg_standard"):
		var part := model.get_node_or_null(slot) as MeshInstance3D
		assert_object(part).override_failure_message(slot).is_not_null()
		assert_int(GunPartMeshes.triangles(part.mesh)).override_failure_message(slot).is_greater(0)


## Stats of a named build, failing the test if it does not assemble.
func _stats(build_name: String) -> Dictionary:
	var result := GunAssembly.assemble_named(build_name)
	assert_bool(result["ok"]).override_failure_message("%s: %s" % [build_name, result["errors"]]).is_true()
	return result["stats"]


func test_the_three_new_pistols_take_their_numbers_from_the_data() -> void:
	var parts := GunAssembly.catalogue()
	for pair: Array in [["fn57_standard", "rcv_fn57"], ["deagle_standard", "rcv_deagle"], ["python_standard", "rcv_python"]]:
		var stats := _stats(pair[0])
		var receiver: Dictionary = parts[pair[1]]
		for key: String in ["damage", "rounds_per_minute", "spread_degrees", "reload_seconds"]:
			assert_float(float(stats[key])).override_failure_message("%s %s" % [pair[0], key]).is_equal_approx(float(receiver["stats"][key]), 0.0001)
		assert_str(GunAssembly.weapon_slot_of(GunAssembly.build(pair[0]))).is_equal("secondary")
		assert_str(str(receiver["fire_mode"])).is_equal("semi")
	assert_float(_stats("fn57_standard")["magazine"]).is_equal(float(parts["mag_fn57_20"]["stats"]["magazine"]))
	assert_float(_stats("deagle_standard")["magazine"]).is_equal(float(parts["mag_deagle_7"]["stats"]["magazine"]))
	# The revolver's six rounds are the frame's own: it has no magazine part.
	assert_float(_stats("python_standard")["magazine"]).is_equal(float(parts["rcv_python"]["stats"]["magazine"]))


func test_the_pistols_play_their_roles() -> void:
	var pistol := _stats("pistol_standard")
	var fn := _stats("fn57_standard")
	var eagle := _stats("deagle_standard")
	var python := _stats("python_standard")
	var feel: Dictionary = Data.load_json(HitscanWeapon.CONFIG)["rifle"]
	var parts := GunAssembly.catalogue()
	# Soldiers have 100 health: the .50 drops one in two body shots, the .357 in three.
	assert_float(eagle["damage"]).is_greater_equal(50.0)
	assert_float(python["damage"] * 2.0).is_less(100.0)
	assert_float(python["damage"] * 3.0).is_greater_equal(100.0)
	# The 5.7 hits light, fires fast and holds the most; quick to draw and to recover.
	assert_float(fn["damage"]).is_less(pistol["damage"])
	assert_float(fn["rounds_per_minute"]).is_greater(pistol["rounds_per_minute"])
	assert_float(fn["magazine"]).is_greater(pistol["magazine"])
	assert_float(float(parts["rcv_fn57"]["draw_seconds"])).is_less(float(feel["draw_seconds"]))
	assert_float(float(parts["rcv_fn57"]["recoil_recovery"])).is_greater(float(feel["recoil_recovery"]))
	# The .50 kicks hardest, fires slowest, recovers and draws slowly and sprays on the move.
	assert_float(eagle["recoil_pitch_degrees"]).is_greater(python["recoil_pitch_degrees"])
	assert_float(eagle["rounds_per_minute"]).is_less(python["rounds_per_minute"])
	assert_float(eagle["reload_seconds"]).is_greater(pistol["reload_seconds"])
	assert_float(float(parts["rcv_deagle"]["recoil_recovery"])).is_less(float(feel["recoil_recovery"]))
	assert_float(float(parts["rcv_deagle"]["draw_seconds"])).is_greater(float(feel["draw_seconds"]))
	assert_float(float(parts["rcv_deagle"]["moving_spread_multiplier"])).is_greater(1.5)
	assert_float(float(feel["moving_spread_multiplier"])).is_equal(1.0)
	# The revolver is the tightest of the three and loads a round at a time.
	assert_float(python["spread_degrees"]).is_less(fn["spread_degrees"])
	assert_float(python["spread_degrees"]).is_less(eagle["spread_degrees"])
	assert_bool(GunAssembly.round_by_round_of(GunAssembly.build("python_standard"))).is_true()
	assert_bool(GunAssembly.round_by_round_of(GunAssembly.build("deagle_standard"))).is_false()


func test_the_five_seven_takes_the_long_magazine_and_muzzle_devices() -> void:
	var build := GunAssembly.build("fn57_standard").duplicate()
	build["fn_magazine"] = "mag_fn57_30"
	for muzzle: String in ["muz_pistol_comp", "muz_pistol_supp"]:
		build["pistol_muzzle"] = muzzle
		build["pistol_optic"] = "opt_pistol_dot"
		var result := WeaponBuild.assemble(GunAssembly.catalogue(), build)
		assert_bool(result["ok"]).override_failure_message(str(result["errors"])).is_true()
		assert_float(result["stats"]["magazine"]).is_equal(30.0)
		var model: Node3D = auto_free(GunAssembly.build_model(build))
		add_child(model)
		# The device's own muzzle is out past the slide's.
		assert_float((model.get_node("Muzzle") as Node3D).position.z).is_less(-0.16)


func test_the_eagle_takes_a_sight_and_the_revolver_nothing_extra() -> void:
	var eagle := GunAssembly.build("deagle_standard").duplicate()
	eagle["pistol_optic"] = "opt_pistol_dot"
	assert_bool(WeaponBuild.assemble(GunAssembly.catalogue(), eagle)["ok"]).is_true()
	eagle.erase("pistol_optic")
	eagle["pistol_muzzle"] = "muz_pistol_supp"
	assert_bool(WeaponBuild.assemble(GunAssembly.catalogue(), eagle)["ok"]).is_false()
	var extras := {"pistol_muzzle": "muz_pistol_comp", "pistol_optic": "opt_pistol_dot", "pistol_magazine": "mag_pistol_15"}
	for slot: String in extras:
		var python := GunAssembly.build("python_standard").duplicate()
		python[slot] = extras[slot]
		assert_bool(WeaponBuild.assemble(GunAssembly.catalogue(), python)["ok"]).override_failure_message(slot).is_false()


func test_the_pistols_voxel_parts_hang_where_their_frames_mount_them() -> void:
	var cases := [
		["fn57_standard", VoxFiveSeven.MOUNTS, {"fn_slide": "slide", "fn_magazine": "mag20"}],
		["deagle_standard", VoxDesertEagle.MOUNTS, {"de_barrel": "barrel", "de_magazine": "magazine"}],
		["python_standard", VoxPython.MOUNTS, {"rv_barrel": "barrel", "rv_grip": "grip"}],
	]
	for case: Array in cases:
		var slots := GunAssembly.build(case[0])
		var receiver := GunAssembly.receiver_of(slots)
		var mounts: Dictionary = case[1]
		var by_slot: Dictionary = case[2]
		for slot: String in by_slot:
			var a: Array = receiver["mounts"][slot]
			assert_vector(Vector3(a[0], a[1], a[2])).override_failure_message("%s %s" % [case[0], slot]).is_equal_approx(mounts[by_slot[slot]], Vector3.ONE * 0.0001)
		var model: Node3D = auto_free(GunAssembly.build_model(slots))
		add_child(model)
		for marker: String in ["GripR", "GripL", "Sight", "Muzzle"]:
			assert_object(model.get_node_or_null(marker)).override_failure_message("%s %s" % [case[0], marker]).is_not_null()
		for slot: String in slots:
			var part := model.get_node_or_null(slot) as MeshInstance3D
			assert_object(part).override_failure_message("%s %s" % [case[0], slot]).is_not_null()
			assert_int(GunPartMeshes.triangles(part.mesh)).override_failure_message("%s %s" % [case[0], slot]).is_greater(0)
	# Markers sit where the models put the grips and sights.
	var fn_grip: Array = GunAssembly.catalogue()["rcv_fn57"]["markers"]["GripR"]
	assert_vector(Vector3(fn_grip[0], fn_grip[1], fn_grip[2])).is_equal_approx(VoxFiveSeven.GRIP, Vector3.ONE * 0.0001)
	var fn_sight: Array = GunAssembly.catalogue()["sld_fn57"]["markers"]["Sight"]
	assert_float(float(fn_sight[1])).is_equal_approx(VoxFiveSeven.SIGHT_LINE, 0.0001)
	var de_grip: Array = GunAssembly.catalogue()["rcv_deagle"]["markers"]["GripR"]
	assert_vector(Vector3(de_grip[0], de_grip[1], de_grip[2])).is_equal_approx(VoxDesertEagle.GRIP, Vector3.ONE * 0.0001)
	var de_sight: Array = GunAssembly.catalogue()["rcv_deagle"]["markers"]["Sight"]
	assert_float(float(de_sight[1])).is_equal_approx(VoxDesertEagle.SIGHT_LINE, 0.0001)
	var py_grip: Array = GunAssembly.catalogue()["rcv_python"]["markers"]["GripR"]
	assert_vector(Vector3(py_grip[0], py_grip[1], py_grip[2])).is_equal_approx(VoxPython.GRIP, Vector3.ONE * 0.0001)
	var py_sight: Array = GunAssembly.catalogue()["rcv_python"]["markers"]["Sight"]
	assert_float(float(py_sight[1])).is_equal_approx(VoxPython.SIGHT_LINE, 0.0001)
	var py_muzzle: Array = GunAssembly.catalogue()["bar_python_6"]["markers"]["Muzzle"]
	assert_float(float(py_muzzle[2])).is_equal_approx(-VoxPython.BARREL_LENGTH, 0.0001)
