extends GdUnitTestSuite
## Craters are kept: the world lists every dig in its saved state, and a restored state digs
## them again, so the ground is as broken after a restart (and for a late joiner) as before.

const MODULE := "res://modules/world/world_module.gd"

var _world: Node


func before_test() -> void:
	_world = auto_free((load(MODULE) as GDScript).new())
	add_child(_world)
	var voxels: VoxelWorld = _world.get(&"_voxels")
	for i in 600:
		if voxels.is_ready_at(voxels.home):
			break
		await get_tree().physics_frame


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
