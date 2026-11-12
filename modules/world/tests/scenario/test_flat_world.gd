extends GdUnitTestSuite
## `--world=flat` loads the flat test world: a level plane with collision that answers like
## the terrain does, announced at once with no terrain or scenery to stream.

const MODULE := "res://modules/world/world_module.gd"

var _announced: Dictionary = {}


func before_test() -> void:
	Net.extra_args = PackedStringArray(["--world=flat"])
	_announced = {}
	EventBus.subscribe(&"world.ready", _on_ready)


func after_test() -> void:
	Net.extra_args = PackedStringArray()
	EventBus.unsubscribe(&"world.ready", _on_ready)


func _on_ready(p: Dictionary) -> void:
	_announced = p


func test_the_flat_world_loads_level_and_ready() -> void:
	var module: Node = auto_free((load(MODULE) as GDScript).new())
	add_child(module)
	for i in 30:
		await get_tree().physics_frame
		if not _announced.is_empty():
			break
	assert_dict(_announced).is_not_empty()
	var ground := get_tree().get_first_node_in_group(&"ground")
	assert_object(ground).is_instanceof(FlatGround)
	assert_float(float(ground.call(&"surface_height", 120.0, -300.0))).is_equal(0.0)
	assert_vector(ground.call(&"road_point", 50.0) as Vector3).is_equal(Vector3(0, 0, -50))
	assert_object(get_tree().get_first_node_in_group(&"terrain")).is_null()
	var space := (ground as Node3D).get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(200, 10, -200), Vector3(200, -10, -200)))
	assert_float((hit["position"] as Vector3).y).is_equal_approx(0.0, 0.01)
