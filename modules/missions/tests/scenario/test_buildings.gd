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
	_missions.call(&"server_choose", 61, 0)
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
	var crate := _missions.get(&"_objective_crate") as Node3D
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
