extends GdUnitTestSuite
## Craters are kept: the world lists every dig in its saved state, and a restored state digs
## them again, so the ground is as broken after a restart (and for a late joiner) as before.

const MODULE := "res://modules/world/world_module.gd"

var _world: Node


func before_test() -> void:
	_world = auto_free((load(MODULE) as GDScript).new())
	add_child(_world)
	await _until_loaded()
	var voxels: VoxelWorld = _world.get(&"_voxels")
	for i in 600:
		if voxels.is_ready_at(voxels.home):
			break
		await get_tree().physics_frame


## The map builds on a worker thread; the world scene is in once it is done.
func _until_loaded() -> void:
	for i in 600:
		if _world.get(&"_voxels") != null:
			return
		await get_tree().process_frame
	assert_object(_world.get(&"_voxels")).override_failure_message("the world did not load").is_not_null()


## Craters that arrive while the map is still building (a late joiner's list, an explosion
## replayed from the server) are dug once the world is in, not dropped.
func test_craters_sent_while_the_map_builds_are_dug_once_it_is_in() -> void:
	var voxels: VoxelWorld = _world.get(&"_voxels")
	var spot := voxels.home + Vector3(6.0, 0.0, -30.0)
	var at := Vector3(spot.x, voxels.ground_height(spot.x, spot.z), spot.z)
	# One world at a time: the map selection is shared.
	remove_child(_world)
	_world.free()
	var early: Node = auto_free((load(MODULE) as GDScript).new())
	add_child(early)
	assert_object(early.get(&"_voxels")).is_null()
	early.call(&"_receive_digs", [[at.x, at.y, at.z, 2.0]])
	for i in 600:
		if early.get(&"_voxels") != null:
			break
		await get_tree().process_frame
	var late: VoxelWorld = early.get(&"_voxels")
	assert_object(late).is_not_null()
	assert_int(late.dig_log().size()).is_equal(1)


func test_a_crater_is_listed_and_dug_again_from_the_saved_state() -> void:
	var voxels: VoxelWorld = _world.get(&"_voxels")
	# Near where players start (the camp on a generated map), where the ground is built.
	var spot := voxels.home + Vector3(6.0, 0.0, -30.0)
	var at := Vector3(spot.x, voxels.ground_height(spot.x, spot.z), spot.z)
	var before := voxels.surface_height(at.x, at.z)
	var saved := {"digs": [[at.x, at.y, at.z, 2.0]], "felled": []}
	_world.call(&"server_restore_world_state", 3, saved)
	assert_float(voxels.surface_height(at.x, at.z)).is_less(before - 0.5)
	var state: Dictionary = _world.call(&"server_world_state")
	assert_int((state["digs"] as Array).size()).is_equal(1)


func test_an_unknown_version_starts_undamaged() -> void:
	var voxels: VoxelWorld = _world.get(&"_voxels")
	Log.begin_capture()
	_world.call(&"server_restore_world_state", 99, {"digs": [[0, 0, -30, 2.0]]})
	Log.end_capture()
	assert_int(voxels.dig_log().size()).is_equal(0)
