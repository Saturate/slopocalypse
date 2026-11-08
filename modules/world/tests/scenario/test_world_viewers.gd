extends GdUnitTestSuite
## Every player, enemy and vehicle gets solid ground under it at the same time. The old
## terrain kept collision around one viewer only, so whoever wasn't it fell through (the car
## and the player both did in playtests).

const WORLD := "res://modules/world/scenes/world.tscn"

var _world: Node3D
var _voxels: VoxelWorld


func before_test() -> void:
	_world = await VoxelWorld.add_and_wait(self, WORLD)
	_voxels = _world.get_node("Terrain")


func after_test() -> void:
	_world.free()


func _follower(group: StringName, at: Vector3) -> Node3D:
	var n: Node3D = auto_free(Node3D.new())
	n.add_to_group(group)
	add_child(n)
	n.global_position = at
	return n


func test_ground_is_solid_under_everyone_at_once() -> void:
	var places := [Vector3(-94, 0, -13), Vector3(40, 0, -700), Vector3(-60, 0, -1500)]
	_follower(&"players", places[0])
	_follower(&"vehicles", places[1])
	_follower(&"enemies", places[2])
	for i in 300:
		await get_tree().process_frame
	for p: Vector3 in places + [Vector3.ZERO]:
		assert_bool(_voxels.is_ready_at(p)).override_failure_message("no ground at %s" % p).is_true()


func test_ground_far_from_everyone_is_let_go() -> void:
	var walker := _follower(&"players", Vector3(0, 0, -800))
	for i in 200:
		await get_tree().process_frame
	assert_bool(_voxels.is_ready_at(Vector3(0, 0, -800))).is_true()
	walker.global_position = Vector3(0, 0, -1600)
	for i in 300:
		await get_tree().process_frame
	assert_bool(_voxels.is_ready_at(Vector3(0, 0, -800))).is_false()
