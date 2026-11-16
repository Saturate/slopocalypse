extends GdUnitTestSuite
## Windows are openings in a building's collision: eyes see through them, intact panes stop
## bullets and bodies on their own glass layer, and a broken pane leaves a real opening.

const MISSIONS := "res://modules/missions/missions_module.gd"
const INVENTORY := "res://modules/inventory/inventory_module.gd"

var _missions: Node


func before_test() -> void:
	add_child(auto_free((load(INVENTORY) as GDScript).new()))
	_missions = auto_free((load(MISSIONS) as GDScript).new())
	add_child(_missions)
	EventBus.publish(&"world.ready", {"spawn": Vector3.ZERO})


static func _road(metres: float) -> Vector3:
	return Vector3(0.0, 0.0, -metres)


func _building(material: String, glass: String) -> MissionBuilding:
	var cfg: Dictionary = (_missions.get(&"config") as Dictionary)["buildings"]
	var entry: Dictionary = MissionLayout.buildings(cfg, 3, _road, 300.0)[0]
	entry["material"] = material
	entry["glass"] = glass
	entry["windows"] = 2
	entry["position"] = Vector3(0, 0, -40)
	var b: MissionBuilding = auto_free(MissionBuilding.new())
	b.spec = entry
	add_child(b)
	b.global_position = entry["position"]
	await get_tree().physics_frame
	return b


## A line through the middle of pane `i` from inside the building to 3 m outside, world space.
func _through(b: MissionBuilding, i: int, offset := Vector3.ZERO) -> Array[Vector3]:
	var box: AABB = (b.get(&"_panes") as Array)[i]["box"]
	var centre := box.get_center() + offset
	var out := Vector3(centre.x, 0.0, centre.z).normalized()
	return [b.global_transform * (centre - out * 1.0), b.global_transform * (centre + out * 3.0)]


func _hit(line: Array[Vector3], mask: int) -> Dictionary:
	return get_tree().root.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(line[0], line[1], mask))


func test_eyes_see_through_a_window_but_not_the_wall_beside_it() -> void:
	var b := await _building("brick", "window_glass")
	assert_int(b.pane_count()).is_greater(0)
	var line := _through(b, 0)
	assert_dict(_hit(line, PhysicsLayers.SOLID | PhysicsLayers.SIGHT)).is_empty()
	var box: AABB = (b.get(&"_panes") as Array)[0]["box"]
	var beside := _through(b, 0, Vector3(0, box.size.y, 0))
	assert_dict(_hit(beside, PhysicsLayers.SOLID | PhysicsLayers.SIGHT)).is_not_empty()


func test_an_intact_pane_stops_bullets_and_bodies_and_belongs_to_its_building() -> void:
	var b := await _building("wood", "window_glass")
	var line := _through(b, 0)
	var shot := _hit(line, PhysicsLayers.BULLETS)
	assert_dict(shot).is_not_empty()
	assert_object(MissionBuilding.of(shot["collider"])).is_same(b)
	assert_dict(_hit(line, PhysicsLayers.SOLID | PhysicsLayers.GLASS)).is_not_empty()
	var player: CharacterBody3D = auto_free((load("res://modules/player/scenes/player.tscn") as PackedScene).instantiate())
	assert_int(player.collision_mask & PhysicsLayers.GLASS).is_equal(PhysicsLayers.GLASS)


func test_a_broken_pane_leaves_an_opening_rounds_fly_through_whole() -> void:
	var b := await _building("wood", "window_glass")
	var line := _through(b, 0)
	b.break_panes([0], false)
	assert_dict(_hit(line, PhysicsLayers.BULLETS)).is_empty()
	await get_tree().physics_frame
	assert_int(b.get_children().filter(func(n: Node) -> bool: return n is PaneBody).size()).is_equal(b.pane_count() - 1)


func test_cracks_in_security_glass_hide_what_is_behind_it() -> void:
	var b := await _building("concrete", "security_glass")
	var line := _through(b, 0)
	assert_float(b.pane_sight_block(0)).is_equal(0.0)
	var at := line[0] + (line[1] - line[0]).normalized()
	for i in 11:
		assert_int(b.server_pane_hit(at, line[0] - line[1])).is_equal(-1)
	assert_bool(b.is_pane_broken(0)).is_false()
	assert_float(b.pane_sight_block(0)).is_equal_approx(0.88, 0.001)
	var pane := _hit(line, PhysicsLayers.GLASS)
	assert_float(float((pane["collider"] as Object).call(&"sight_block_chance"))).is_equal_approx(0.88, 0.001)


func test_window_glass_never_hides_anything() -> void:
	var b := await _building("wood", "window_glass")
	var line := _through(b, 0)
	var at := line[0] + (line[1] - line[0]).normalized()
	assert_int(b.server_pane_hit(at, line[0] - line[1])).is_equal(0)
	assert_float(b.pane_sight_block(0)).is_equal(0.0)


func test_cut_out_leaves_the_boxes_round_a_hole() -> void:
	var wall := AABB(Vector3(0, 0, 0), Vector3(1.2, 1.4, 0.2))
	var window := AABB(Vector3(0.3, 0.5, 0.05), Vector3(0.6, 0.6, 0.05))
	var pieces := MissionBuilding.cut_out(wall, [window])
	var volume := 0.0
	for p in pieces:
		volume += p.get_volume()
		assert_bool(p.intersects(window)).is_false()
	assert_float(volume).is_equal_approx(wall.get_volume() - 0.6 * 0.6 * 0.2, 0.0001)
	assert_int(MissionBuilding.cut_out(wall, [AABB(Vector3(5, 5, 5), Vector3.ONE)]).size()).is_equal(1)
