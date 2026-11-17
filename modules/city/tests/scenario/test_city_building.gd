extends GdUnitTestSuite
## An apartment block you can walk into: its collision is its voxels, so walls stop rounds,
## windows let them through, every floor holds you up, and the stairs take you up a storey.

const PARAMS := {"floors": 3, "stairwells": 1, "seed": 4, "roof": 2}
const PLAYER := "res://modules/player/scenes/player.tscn"

var _building: CityBuilding
var _plan: Dictionary


func before_test() -> void:
	_building = auto_free(CityBuilding.new())
	_building.params = PARAMS
	add_child(_building)
	_plan = _building.plan()
	await get_tree().physics_frame


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, PhysicsLayers.SOLID)
	return _building.get_world_3d().direct_space_state.intersect_ray(query)


func test_its_collision_is_a_few_thousand_boxes_not_a_node_each() -> void:
	assert_int(_building.shape_count()).is_between(100, 5000)
	assert_int(_building.get_child_count()).is_less(5)


func test_a_wall_stops_a_round_and_reports_the_building() -> void:
	var d := float(_plan["depth"])
	var flat: Vector2 = (_plan["flats"] as Array)[0]
	# Between the flat's windows, at head height on the first floor: wall.
	var level := float((_plan["levels"] as Array)[0])
	var x := flat.x + 0.4
	var hit := _ray(Vector3(x, level + 1.6, -d / 2.0 - 5.0), Vector3(x, level + 1.6, 0.0))
	assert_bool(hit.is_empty()).is_false()
	assert_object(hit["collider"]).is_same(_building)


func test_a_round_goes_in_through_a_window() -> void:
	var d := float(_plan["depth"])
	var flat: Vector2 = (_plan["flats"] as Array)[0]
	# Into a pane, clear of the mullion down the middle and the transom across.
	var x := VoxApartment.window_x(flat, 2, 0) + VoxApartment.WINDOW.x / 4.0
	var level := float((_plan["levels"] as Array)[1])
	var y := level + VoxApartment.WINDOW_SILL + VoxApartment.WINDOW.y * 0.35
	var hit := _ray(Vector3(x, y, -d / 2.0 - 5.0), Vector3(x, y, -d / 2.0 + 1.0))
	assert_bool(hit.is_empty()).is_true()


func test_every_floor_holds_you_up_at_its_level() -> void:
	var flat: Vector2 = (_plan["flats"] as Array)[0]
	var inner := VoxApartment.inner_rect(_plan, flat)
	var mid := inner.get_center()
	for level: float in _plan["levels"]:
		var hit := _ray(Vector3(mid.x, level + 1.5, mid.y), Vector3(mid.x, level - 1.0, mid.y))
		assert_bool(hit.is_empty()).is_false()
		assert_float((hit["position"] as Vector3).y).is_equal_approx(level, 0.2)


func test_the_stairs_take_you_up_half_a_storey() -> void:
	var bay: Vector2 = (_plan["bays"] as Array)[0]
	var wall := float(_plan["wall"])
	var inner := Vector2(bay.x + wall / 2.0, bay.y - wall / 2.0)
	var x := (inner.x + (inner.x + inner.y) / 2.0) / 2.0
	var level := float((_plan["levels"] as Array)[0])
	var z := -float(_plan["depth"]) / 2.0 + wall + 0.5
	var player: PlayerController = (load(PLAYER) as PackedScene).instantiate()
	add_child(player)
	# Facing +z, up the first flight.
	player.rotation.y = PI
	player.global_position = Vector3(x, level + 0.05, z)
	for i in 10:
		await get_tree().physics_frame
	player.intent().move = Vector2(0, 1)
	for i in 70:
		await get_tree().physics_frame
	assert_float(player.global_position.y).is_greater(level + VoxApartment.STOREY / 2.0 - 0.3)
	player.free()
