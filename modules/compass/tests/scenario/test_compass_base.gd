extends GdUnitTestSuite
## The compass's base is the camp's centre from the camp layout in `world.ready`, not the
## spawn: the respawn spot sits off to one side of the camp.

const MODULE := "res://modules/compass/compass_module.gd"


func test_the_base_is_the_camp_centre() -> void:
	var module: Node = auto_free((load(MODULE) as GDScript).new())
	add_child(module)
	var camp := CampLayout.new()
	camp.centre = Vector3(120.0, 4.0, -80.0)
	EventBus.publish(&"world.ready", {"spawn": Vector3(130.0, 5.0, -70.0), "camp": camp})
	assert_vector(module.get(&"_base")).is_equal(Vector3(120.0, 4.0, -80.0))
	assert_bool(module.get(&"_has_base")).is_true()
