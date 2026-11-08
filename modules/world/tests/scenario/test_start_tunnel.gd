extends GdUnitTestSuite
## The game starts inside a tunnel: a player at the spawn walks out of the portal onto the
## road, can't get past the cave-in behind them, and can't walk through the tunnel's walls.
## Drives the real player scene on the real world through PlayerIntent.

const WORLD := "res://modules/world/scenes/world.tscn"
const PLAYER := "res://modules/player/scenes/player.tscn"
const CONFIG := "res://modules/world/data/world.json"

var _world: Node3D
var _player: PlayerController
var _start: Dictionary


func before_test() -> void:
	_start = (Data.load_json(CONFIG) as Dictionary)["start"]
	_world = await VoxelWorld.add_and_wait(self, WORLD)
	_player = (load(PLAYER) as PackedScene).instantiate()
	add_child(_player)
	_player.global_position = (_world.get_node("SpawnPoint") as Marker3D).global_position


func after_test() -> void:
	_player.free()
	_world.free()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _landed() -> void:
	for i in 600:
		if _player.is_on_floor():
			break
		await get_tree().physics_frame
	await _frames(10)


func test_the_spawn_is_on_the_tunnel_floor_under_its_roof() -> void:
	await _landed()
	var floor_y := (_world.get_node("Terrain") as VoxelWorld).ground_height(0.0, 0.0)
	assert_float(_player.global_position.y).is_equal_approx(floor_y, 0.15)
	var space := _player.get_world_3d().direct_space_state
	var up := PhysicsRayQueryParameters3D.create(_player.global_position + Vector3.UP * 2.0, _player.global_position + Vector3.UP * 30.0, PhysicsLayers.SOLID)
	assert_bool(space.intersect_ray(up).is_empty()).override_failure_message("no roof over the spawn").is_false()


func test_walking_forward_leaves_the_tunnel() -> void:
	await _landed()
	_player.intent().move = Vector2(0.0, 1.0)
	_player.intent().sprint = true
	var portal: float = _start["portal_z"]
	for i in 600:
		if _player.global_position.z < portal - 4.0:
			break
		await get_tree().physics_frame
	assert_float(_player.global_position.z).is_less(portal - 4.0)


func test_the_cave_in_stops_you_going_back() -> void:
	await _landed()
	_player.intent().move = Vector2(0.0, -1.0)
	_player.intent().sprint = true
	await _frames(480)
	var collapse_start := float(_start["tunnel_end_z"]) - float(_start["collapse_length"])
	assert_float(_player.global_position.z).is_less(collapse_start + 2.5)


func test_the_walls_hold() -> void:
	await _landed()
	var half: float = _start["tunnel_half_width"]
	for side in [1.0, -1.0]:
		_player.intent().move = Vector2(side, 0.0)
		_player.intent().sprint = true
		await _frames(240)
		assert_float(absf(_player.global_position.x)).is_less(half)
		_player.intent().jump = true
		await _frames(60)
		_player.intent().jump = false
		await _frames(60)
		assert_float(absf(_player.global_position.x)).is_less(half)
