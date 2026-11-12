extends GdUnitTestSuite
## Mission zones lay out walk-in buildings from the mission's seed: the same everywhere,
## apart from each other and the road, the objective inside one, gone after the run.

const PLAYER := "res://modules/player/scenes/player.tscn"
const MISSIONS := "res://modules/missions/missions_module.gd"
const INVENTORY := "res://modules/inventory/inventory_module.gd"
const SPAWN := Vector3(0.0, 1.0, 0.0)

var _missions: Node


func before_test() -> void:
	EventBus.subscribe(&"player.move_requested", _on_move)
	add_child(auto_free((load(INVENTORY) as GDScript).new()))
	_missions = auto_free((load(MISSIONS) as GDScript).new())
	add_child(_missions)
	EventBus.publish(&"world.ready", {"spawn": SPAWN})


func after_test() -> void:
	EventBus.unsubscribe(&"player.move_requested", _on_move)


func _on_move(p: Dictionary) -> void:
	(p["player"] as Node3D).global_position = p["position"]


func _cfg() -> Dictionary:
	return (_missions.get(&"config") as Dictionary)["buildings"]


static func _road(metres: float) -> Vector3:
	return Vector3(0.0, 0.0, -metres)


func _ride_out() -> void:
	var player: PlayerController = auto_free((load(PLAYER) as PackedScene).instantiate())
	player.set_meta(&"peer_id", 61)
	player.add_to_group(&"players")
	add_child(player)
	player.set_physics_process(false)
	player.global_position = SPAWN + Vector3(1, 0, 2)
	EventBus.publish(&"player.spawned", {"player": player, "local": false})
	var cfg: Dictionary = _missions.get(&"config")
	var offers: Array = []
	for seed_value in 80:
		offers = (load(MISSIONS) as GDScript).call(&"roll_offers", cfg, seed_value)
		if offers.any(func(o: Dictionary) -> bool: return o["type"] == "smash_and_grab"):
			break
	_missions.set(&"offers", offers)
	var index := offers.find(offers.filter(func(o: Dictionary) -> bool: return o["type"] == "smash_and_grab")[0])
	_missions.call(&"server_choose", 61, index)
	assert_bool(_missions.call(&"server_ride_out")).is_true()
	await get_tree().physics_frame
	await get_tree().physics_frame


func test_the_same_seed_lays_out_the_same_buildings() -> void:
	var a := MissionLayout.buildings(_cfg(), 42, _road, 300.0)
	var b := MissionLayout.buildings(_cfg(), 42, _road, 300.0)
	assert_array(a).is_equal(b)
	assert_int(a.size()).is_between(int(_cfg()["count"][0]), int(_cfg()["count"][1]))


func test_buildings_keep_off_the_road_and_apart() -> void:
	for seed_value in 20:
		var layout := MissionLayout.buildings(_cfg(), seed_value, _road, 300.0)
		for i in layout.size():
			var a: Dictionary = layout[i]
			var at: Vector3 = a["position"]
			# The road runs along x = 0 here; the near wall stays off_road[0] away from it.
			assert_float(absf(at.x) - float(a["depth"]) / 2.0).is_greater_equal(float(_cfg()["off_road"][0]) - 0.01)
			for j in range(i + 1, layout.size()):
				var b: Dictionary = layout[j]
				var gap := Vector2(at.x - (b["position"] as Vector3).x, at.z - (b["position"] as Vector3).z).length()
				assert_float(gap).is_greater(float(a["radius"]) + float(b["radius"]))


func test_doors_face_the_road() -> void:
	for entry: Dictionary in MissionLayout.buildings(_cfg(), 7, _road, 300.0):
		var door := Basis(Vector3.UP, float(entry["yaw"])) * Vector3.FORWARD
		var at: Vector3 = entry["position"]
		assert_float(door.x * -signf(at.x)).is_greater(0.9)


func test_riding_out_builds_them_with_the_drive_inside_one() -> void:
	await _ride_out()
	var nodes := get_tree().get_nodes_in_group(&"mission_buildings")
	assert_int(nodes.size()).is_greater(2)
	var first := nodes[0] as MissionBuilding
	var crate := (_missions.get_node("Type") as MissionType).get(&"_crate") as Node3D
	var local := first.global_transform.affine_inverse() * crate.global_position
	assert_float(absf(local.x)).is_less(float(first.spec["width"]) / 2.0)
	assert_float(absf(local.z)).is_less(float(first.spec["depth"]) / 2.0)


func test_you_can_walk_in_through_the_door_but_not_the_wall() -> void:
	await _ride_out()
	var b := get_tree().get_nodes_in_group(&"mission_buildings")[0] as MissionBuilding
	var space := b.get_world_3d().direct_space_state
	var d := float(b.spec["depth"])
	var w := float(b.spec["width"])
	var outside_door := b.global_transform * Vector3(0, 1.0, -d / 2.0 - 1.5)
	var inside := b.global_transform * Vector3(0, 1.0, 0)
	assert_dict(space.intersect_ray(PhysicsRayQueryParameters3D.create(outside_door, inside))).is_empty()
	var outside_wall := b.global_transform * Vector3(w / 2.0 + 1.5, 1.0, 0)
	assert_dict(space.intersect_ray(PhysicsRayQueryParameters3D.create(outside_wall, inside))).is_not_empty()


func test_the_buildings_go_when_the_run_ends() -> void:
	await _ride_out()
	var player := get_tree().get_nodes_in_group(&"players")[0] as Node3D
	var car := _missions.get(&"_dropoff_car") as Node3D
	player.global_position = car.global_position + Vector3(2, 0, 0)
	_missions.call(&"server_ride_home", player)
	await get_tree().process_frame
	var left := get_tree().get_nodes_in_group(&"mission_buildings").filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	assert_int(left.size()).is_equal(0)


func test_a_blast_beside_a_wall_knocks_a_hole_you_can_see_through() -> void:
	await _ride_out()
	var b := get_tree().get_nodes_in_group(&"mission_buildings")[0] as MissionBuilding
	var w := float(b.spec["width"])
	var outside := b.global_transform * Vector3(w / 2.0 + 1.5, 1.0, 0)
	var inside := b.global_transform * Vector3(0, 1.0, 0)
	var space := b.get_world_3d().direct_space_state
	assert_dict(space.intersect_ray(PhysicsRayQueryParameters3D.create(outside, inside))).is_not_empty()
	var before := b.segment_count()
	# A blast right against the right-hand wall.
	Net.server_broadcast(&"explosion", {"position": b.global_transform * Vector3(w / 2.0 + 0.3, 1.0, 0), "radius": 3.0})
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_dict(space.intersect_ray(PhysicsRayQueryParameters3D.create(outside, inside))).is_empty()
	# The back wall far from it still stands somewhere.
	var standing := 0
	for i in before:
		if not b.is_broken(i):
			standing += 1
	assert_int(standing).is_greater(0)
	# The layout entry remembers the hole for anyone who joins later.
	var entry: Dictionary = (_missions.get(&"buildings") as Array)[0]
	assert_int((entry.get("broken", []) as Array).size()).is_greater(0)


func test_a_building_built_from_an_entry_with_holes_has_them() -> void:
	await _ride_out()
	var entry: Dictionary = ((_missions.get(&"buildings") as Array)[0] as Dictionary).duplicate()
	entry["broken"] = [0, 1]
	var copy: MissionBuilding = auto_free(MissionBuilding.new())
	copy.spec = entry
	add_child(copy)
	assert_bool(copy.is_broken(0)).is_true()
	assert_bool(copy.is_broken(1)).is_true()
	assert_bool(copy.is_broken(2)).is_false()


func test_a_faraway_blast_leaves_it_whole() -> void:
	await _ride_out()
	var b := get_tree().get_nodes_in_group(&"mission_buildings")[0] as MissionBuilding
	Net.server_broadcast(&"explosion", {"position": b.global_position + Vector3(40, 0, 0), "radius": 3.0})
	await get_tree().physics_frame
	for i in b.segment_count():
		assert_bool(b.is_broken(i)).is_false()


## A building of `material`, on its own, for the bullet tests.
func _building(material: String) -> MissionBuilding:
	var entry: Dictionary = MissionLayout.buildings(_cfg(), 3, _road, 300.0)[0]
	entry["material"] = material
	# Windows on the side walls, at the middle (see VoxShed's window spots).
	entry["windows"] = 2
	entry["position"] = Vector3(0, 0, -40)
	var b: MissionBuilding = auto_free(MissionBuilding.new())
	b.spec = entry
	b.material_cfg = VoxMaterials.named(material)
	add_child(b)
	b.global_position = entry["position"]
	return b


func test_rifle_rounds_break_a_wooden_wall_piece() -> void:
	var b := _building("wood")
	var w := float(b.spec["width"])
	var point := b.global_transform * Vector3(w / 2.0, 0.6, 0.0)
	var id := b.segment_at(point)
	assert_int(id).is_greater_equal(0)
	var broke := -1
	for i in 10:
		broke = b.server_shot(point, 25.0)
		if broke >= 0:
			break
	assert_int(broke).is_equal(id)


func test_rifle_rounds_only_chip_concrete_but_a_blast_still_breaks_it() -> void:
	var b := _building("concrete")
	var w := float(b.spec["width"])
	var point := b.global_transform * Vector3(w / 2.0, 0.6, 0.0)
	for i in 40:
		assert_int(b.server_shot(point, 25.0)).is_equal(-1)
	assert_int(b.server_blast(point + b.global_transform.basis.x * 0.3, 3.0, 140.0, 1.6).size()).is_greater(0)


func test_brick_shrugs_off_rifle_rounds_but_a_charge_breaks_it() -> void:
	var b := _building("brick")
	var w := float(b.spec["width"])
	var point := b.global_transform * Vector3(w / 2.0, 0.6, 0.0)
	var inward := -b.global_transform.basis.x
	assert_str(str(b.struck_rules(point, inward)["name"])).is_equal("brick")
	for i in 40:
		assert_int(b.server_shot(point, 25.0, inward)).is_equal(-1)
	assert_int(b.server_blast(point + b.global_transform.basis.x * 0.3, 3.0, 150.0, 1.6).size()).is_greater(0)


func test_a_wooden_frame_in_a_concrete_wall_does_not_make_the_wall_easy_to_break() -> void:
	var b := _building("concrete")
	var w := float(b.spec["width"])
	# The bottom bar of the right-hand window's wooden frame.
	var point := b.global_transform * Vector3(w / 2.0, MissionBuilding.SLAB + VoxShed.WINDOW_SILL - 0.07, 0.0)
	var inward := -b.global_transform.basis.x
	assert_str(str(b.struck_rules(point, inward)["name"])).is_equal("wood")
	for i in 40:
		assert_int(b.server_shot(point, 25.0, inward)).is_equal(-1)


func test_shooting_a_pane_does_no_structural_damage() -> void:
	var b := _building("wood")
	var w := float(b.spec["width"])
	var point := b.global_transform * Vector3(w / 2.0, MissionBuilding.SLAB + VoxShed.WINDOW_SILL + VoxShed.WINDOW.y / 2.0, 0.0)
	var inward := -b.global_transform.basis.x
	assert_str(str(b.struck_rules(point, inward)["name"])).is_equal("window_glass")
	for i in 20:
		assert_int(b.server_shot(point, 25.0, inward)).is_equal(-1)


func test_the_server_carves_bullet_holes_so_later_rounds_go_into_them() -> void:
	var b := _building("wood")
	var w := float(b.spec["width"])
	var point := b.global_transform * Vector3(w / 2.0, 0.6, 0.0)
	var inward := -b.global_transform.basis.x
	assert_vector(b.struck_voxel(point, inward)).is_not_equal(Vector3.INF)
	var through := false
	for i in 8:
		b.bullet_mark(point, inward)
		if b.struck_voxel(point, inward) == Vector3.INF:
			through = true
			break
	assert_bool(through).override_failure_message("a few rounds in the same spot should hole a plank wall through").is_true()


func test_rounds_go_through_planks_and_glass_but_not_brick_or_concrete() -> void:
	var low := Vector3(0.0, 0.6, 0.0)
	var pane := Vector3(0.0, MissionBuilding.SLAB + VoxShed.WINDOW_SILL + VoxShed.WINDOW.y / 2.0, 0.0)
	for case: Array in [["wood", low, 0.6], ["wood", pane, 0.9], ["brick", low, 0.0], ["concrete", low, 0.0]]:
		var b := _building(str(case[0]))
		var w := float(b.spec["width"])
		var local: Vector3 = case[1]
		var point := b.global_transform * Vector3(w / 2.0, local.y, 0.0)
		var inward := -b.global_transform.basis.x
		var exit := b.bullet_exit(point, inward, 25.0)
		var label := "%s at %.2f m" % [case[0], local.y]
		if float(case[2]) == 0.0:
			assert_bool(exit.is_empty()).override_failure_message(label + " should stop it").is_true()
			continue
		assert_bool(exit.is_empty()).override_failure_message(label + " should let it through").is_false()
		assert_float(float(exit["scale"])).override_failure_message(label).is_equal_approx(float(case[2]), 0.001)
		# Out the far side of the wall, inside the building.
		var out := b.global_transform.affine_inverse() * (exit["exit"] as Vector3)
		assert_float(out.x).override_failure_message(label).is_less(w / 2.0 - 0.1)


func test_a_round_into_a_hole_carries_on_whole() -> void:
	var b := _building("concrete")
	var w := float(b.spec["width"])
	var point := b.global_transform * Vector3(w / 2.0, 0.6, 0.0)
	var inward := -b.global_transform.basis.x
	assert_bool(b.bullet_exit(point, inward, 25.0).is_empty()).is_true()
	var model: VoxelModel = b.get(&"_model")
	var local := b.global_transform.affine_inverse() * point
	model.carve_box(local - Vector3(0.6, 0.3, 0.3), local + Vector3(0.1, 0.3, 0.3))
	assert_float(float(b.bullet_exit(point, inward, 25.0).get("scale", 0.0))).is_equal(1.0)


## A building whose right-hand window has `glass` panes, and that pane's centre with the way in.
func _pane(glass: String) -> Array:
	var entry: Dictionary = MissionLayout.buildings(_cfg(), 3, _road, 300.0)[0]
	entry["material"] = "wood"
	entry["windows"] = 2
	entry["glass"] = glass
	entry["position"] = Vector3(0, 0, -40)
	var b: MissionBuilding = auto_free(MissionBuilding.new())
	b.spec = entry
	add_child(b)
	b.global_position = entry["position"]
	var w := float(entry["width"])
	var point := b.global_transform * Vector3(w / 2.0, MissionBuilding.SLAB + VoxShed.WINDOW_SILL + VoxShed.WINDOW.y / 2.0, 0.0)
	return [b, point, -b.global_transform.basis.x]


func test_a_window_pane_goes_on_the_first_round_and_leaves_its_frame() -> void:
	var c := _pane("window_glass")
	var b: MissionBuilding = c[0]
	assert_int(b.pane_count()).is_greater_equal(2)
	var pane := b.server_pane_hit(c[1], c[2])
	assert_int(pane).is_greater_equal(0)
	b.break_panes([pane], false)
	assert_bool(b.is_pane_broken(pane)).is_true()
	# The glass is gone, so the next round flies on through the opening.
	assert_float(float(b.bullet_exit(c[1], c[2], 25.0).get("scale", 0.0))).is_equal(1.0)
	var frame := b.global_transform * Vector3(float(b.spec["width"]) / 2.0, MissionBuilding.SLAB + VoxShed.WINDOW_SILL - 0.07, 0.0)
	assert_str(str(b.struck_rules(frame, c[2])["name"])).is_equal("wood")


func test_security_glass_stops_rounds_cracks_and_gives_out_after_twelve() -> void:
	var c := _pane("security_glass")
	var b: MissionBuilding = c[0]
	assert_bool(b.bullet_exit(c[1], c[2], 25.0).is_empty()).is_true()
	var model: VoxelModel = b.get(&"_model")
	var v := b.struck_voxel(c[1], c[2])
	var before := model.colour_at(v)
	var hits := int(VoxMaterials.named("security_glass")["hits_to_break"])
	for i in hits - 1:
		assert_int(b.server_pane_hit(c[1], c[2])).is_equal(-1)
	b.bullet_mark(c[1], c[2])
	assert_float(model.colour_at(v).v).is_greater(before.v)
	assert_int(b.server_pane_hit(c[1], c[2])).is_greater_equal(0)


func test_a_blast_takes_security_glass_out_at_once() -> void:
	var c := _pane("security_glass")
	var b: MissionBuilding = c[0]
	var pane := b.pane_at(c[1], c[2])
	assert_bool(b.server_blast_panes((c[1] as Vector3) - (c[2] as Vector3) * 0.5, 2.5, 1.6).has(pane)).is_true()


func test_a_late_joiner_sees_the_same_panes_gone() -> void:
	var c := _pane("window_glass")
	var first: MissionBuilding = c[0]
	var pane := first.pane_at(c[1], c[2])
	var entry: Dictionary = (first.spec as Dictionary).duplicate()
	entry["panes_broken"] = [pane]
	var late: MissionBuilding = auto_free(MissionBuilding.new())
	late.spec = entry
	add_child(late)
	late.global_position = entry["position"]
	assert_bool(late.is_pane_broken(pane)).is_true()
	assert_int(late.pane_at(c[1], c[2])).is_equal(-1)


## A spot on the right-hand wall, below the window, where a round strikes a brick (not a
## joint), with the way in.
func _brick_spot(b: MissionBuilding) -> Array:
	var w := float(b.spec["width"])
	var inward := -b.global_transform.basis.x
	for i in 40:
		var point := b.global_transform * Vector3(w / 2.0, 0.4 + i * 0.02, -1.0 + i * 0.03)
		if str(b.struck_rules(point, inward)["name"]) == "brick":
			return [point, inward]
	return []


func test_four_rifle_rounds_knock_out_one_brick_and_leave_the_mortar() -> void:
	var b := _building("brick")
	var spot := _brick_spot(b)
	assert_array(spot).is_not_empty()
	for i in 3:
		assert_vector(b.server_brick_hit(spot[0], spot[1], 25.0)).is_equal(Vector3.INF)
	var inside := b.server_brick_hit(spot[0], spot[1], 25.0)
	assert_vector(inside).is_not_equal(Vector3.INF)
	var model: VoxelModel = b.get(&"_model")
	var brick := VoxMaterials.index_of("brick")
	var box := model.component_at(inside, brick, MissionBuilding.BRICK_CAP)
	var mortar_before := model.count_material(box.grow(b.voxel).position, box.grow(b.voxel).end, VoxMaterials.index_of("mortar"))
	b.knock_out([inside], false)
	assert_int(model.material_at(inside)).is_equal(0)
	assert_int(model.count_material(box.position, box.end, brick)).is_equal(0)
	assert_int(model.count_material(box.grow(b.voxel).position, box.grow(b.voxel).end, VoxMaterials.index_of("mortar"))).is_equal(mortar_before)


func test_a_pistol_takes_a_round_more() -> void:
	var b := _building("brick")
	var spot := _brick_spot(b)
	for i in 4:
		assert_vector(b.server_brick_hit(spot[0], spot[1], 20.0)).is_equal(Vector3.INF)
	assert_vector(b.server_brick_hit(spot[0], spot[1], 20.0)).is_not_equal(Vector3.INF)


func test_a_wall_piece_that_loses_most_of_its_bricks_gives_way() -> void:
	var b := _building("brick")
	var w := float(b.spec["width"])
	var point := b.global_transform * Vector3(w / 2.0, 0.6, 0.0)
	var id := b.segment_at(point)
	assert_array(b.server_weakened()).is_empty()
	var model: VoxelModel = b.get(&"_model")
	var brick := VoxMaterials.index_of("brick")
	var seg: AABB = b.call(&"_carve_box", id)
	# Knock out every brick in that piece, one point per brick found.
	var points: Array = []
	var y := seg.position.y + b.voxel * 0.5
	while y < seg.end.y:
		var z := seg.position.z + b.voxel * 0.5
		while z < seg.end.z:
			var p := Vector3(w / 2.0 - b.voxel * 0.5, y, z)
			if model.material_at(p) == brick:
				points.append(p)
				b.knock_out([p], false)
			z += b.voxel
		y += b.voxel
	assert_int(points.size()).is_greater(3)
	assert_bool(b.server_weakened().has(id)).is_true()


func test_a_late_joiner_sees_the_same_bricks_gone() -> void:
	var b := _building("brick")
	var spot := _brick_spot(b)
	var inside := b.struck_voxel(spot[0], spot[1])
	var entry: Dictionary = (b.spec as Dictionary).duplicate()
	entry["knocked"] = [inside]
	var late: MissionBuilding = auto_free(MissionBuilding.new())
	late.spec = entry
	late.material_cfg = VoxMaterials.named("brick")
	add_child(late)
	late.global_position = entry["position"]
	var model: VoxelModel = late.get(&"_model")
	assert_int(model.material_at(inside)).is_equal(0)


func test_a_mission_can_ask_for_concrete() -> void:
	var cfg := _cfg().duplicate()
	cfg["material"] = "concrete"
	for entry: Dictionary in MissionLayout.buildings(cfg, 9, _road, 300.0):
		assert_str(str(entry["material"])).is_equal("concrete")


func _player_at(peer: int, at: Vector3) -> PlayerController:
	var player: PlayerController = auto_free((load(PLAYER) as PackedScene).instantiate())
	player.set_meta(&"peer_id", peer)
	player.add_to_group(&"players")
	add_child(player)
	player.set_physics_process(false)
	player.global_position = at
	return player


func test_breaking_the_walls_brings_the_roof_down_on_whoever_is_under_it() -> void:
	await _ride_out()
	var b := get_tree().get_nodes_in_group(&"mission_buildings")[0] as MissionBuilding
	var w := float(b.spec["width"])
	var wh := float(b.spec["wall_height"])
	var under := _player_at(62, b.global_transform * Vector3(0, MissionBuilding.SLAB, 0))
	var beside := _player_at(63, b.global_transform * Vector3(w / 2.0 + 1.0, 0.0, 0))
	var walls: Array[int] = []
	var roof: Array[int] = []
	for id in b.segment_count():
		var box := MissionBuilding.segments(w, float(b.spec["depth"]), wh, b.segment_size)[id]
		if box.position.y >= wh - 0.01:
			roof.append(id)
		else:
			walls.append(id)
	_missions.call(&"_server_broke", 0, walls)
	await get_tree().physics_frame
	# The roof lost its collision with the walls.
	for id in roof:
		assert_bool(b.is_broken(id)).override_failure_message("roof piece %d still up" % id).is_true()
	var under_health := under.get_node("Health") as HealthComponent
	var beside_health := beside.get_node("Health") as HealthComponent
	var full := under_health.max_health
	# Nobody is hurt before it lands.
	assert_float(under_health.health).is_equal(full)
	await get_tree().create_timer(b.fall_seconds + 0.2).timeout
	assert_float(under_health.health).is_equal(full - float(_cfg()["fall_damage"]))
	assert_float(beside_health.health).is_equal(beside_health.max_health)
	# A late joiner builds the same holes from the layout entry.
	var entry: Dictionary = ((_missions.get(&"buildings") as Array)[0] as Dictionary).duplicate()
	var copy: MissionBuilding = auto_free(MissionBuilding.new())
	copy.spec = entry
	add_child(copy)
	for id in b.segment_count():
		assert_bool(copy.is_broken(id)).is_equal(b.is_broken(id))


func test_one_broken_wall_piece_leaves_the_roof_up() -> void:
	await _ride_out()
	var b := get_tree().get_nodes_in_group(&"mission_buildings")[0] as MissionBuilding
	var w := float(b.spec["width"])
	var id := b.segment_at(b.global_transform * Vector3(w / 2.0, 0.5, 0.0))
	assert_int(id).is_greater_equal(0)
	assert_array(b.server_unsupported([id] as Array[int])).is_empty()
