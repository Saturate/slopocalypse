extends GdUnitTestSuite
## Nobody leaves the world: walls stop walkers at the edge, and anyone who still gets under
## the ground is put back on top.

const WORLD := "res://modules/world/scenes/world.tscn"
const PLAYER := "res://modules/player/scenes/player.tscn"
const PLAYER_MODULE := "res://modules/player/player_module.gd"

var _world: Node3D


func before_test() -> void:
	_world = (load(WORLD) as PackedScene).instantiate()
	add_child(_world)


func after_test() -> void:
	_world.free()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func test_walking_into_the_edge_stops_at_the_wall() -> void:
	var player: PlayerController = auto_free((load(PLAYER) as PackedScene).instantiate())
	add_child(player)
	var data: Dictionary = Data.load_json("res://modules/world/data/world.json")
	var half: float = float(data["size"]) / 2.0
	# Near the north edge, facing north (-Z), sprinting outwards. This tests the walls, not voxel streaming (test_voxel_digging covers that), so give the
	# player a flat floor near the edge instead of waiting for terrain to stream in there.
	var floor_y := 60.0
	var floor_body: StaticBody3D = auto_free(StaticBody3D.new())
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(40.0, 1.0, 60.0)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	add_child(floor_body)
	floor_body.global_position = Vector3(0.0, floor_y - 0.5, -(half - 10.0))
	player.global_position = Vector3(0.0, floor_y + 0.2, -(half - 10.0))
	await _frames(30)
	player.intent().move = Vector2(0.0, 1.0)
	player.intent().sprint = true
	await _frames(240)
	assert_float(player.global_position.z).is_greater(-half)


func test_falling_through_the_ground_puts_you_back_on_top_where_you_were() -> void:
	var module: Node = auto_free((load(PLAYER_MODULE) as GDScript).new())
	add_child(module)
	EventBus.publish(&"world.ready", {"spawn": Vector3(1.0, 2.0, 3.0), "kill_y": -40.0, "rescue_depth": 6.0})
	var player: PlayerController = module.players()[0]
	var voxels: VoxelWorld = _world.get_node("Terrain")
	var ground := voxels.ground_height(30.0, -20.0)
	Log.begin_capture()
	player.global_position = Vector3(30.0, ground - 10.0, -20.0)
	await _frames(2)
	var log_text := LogCapture.text(Log.end_capture())
	assert_vector(player.global_position).is_equal_approx(Vector3(30.0, ground + 1.0, -20.0), Vector3.ONE * 0.05)
	assert_str(log_text).contains("fell through the ground")
	# Held there until the terrain under them has collision, not dropped through it again.
	assert_bool(player.is_physics_processing()).is_false()
