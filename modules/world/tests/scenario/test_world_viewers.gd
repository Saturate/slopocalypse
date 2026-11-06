extends GdUnitTestSuite
## Terrain collision only exists near a VoxelViewer, so everything that moves around on its
## own must carry one: players, and cars while someone drives them (the driver's viewer
## stays with their parked body). A car without one fell out of the world in a playtest.

const MODULE := "res://modules/world/world_module.gd"

var _module: Node


func before_test() -> void:
	_module = (load(MODULE) as GDScript).new()
	add_child(_module)


func after_test() -> void:
	_module.free()


func test_spawned_players_get_a_viewer() -> void:
	var player: Node3D = auto_free(Node3D.new())
	add_child(player)
	EventBus.publish(&"player.spawned", {"player": player, "local": true})
	assert_object(player.get_node_or_null("VoxelViewer")).is_not_null()


func test_driven_cars_get_a_viewer_once() -> void:
	var car: Node3D = auto_free(Node3D.new())
	add_child(car)
	EventBus.publish(&"car.entered", {"car": car, "player": null})
	EventBus.publish(&"car.entered", {"car": car, "player": null})
	var viewers := car.get_children().filter(func(c: Node) -> bool: return c is VoxelViewer)
	assert_int(viewers.size()).is_equal(1)
