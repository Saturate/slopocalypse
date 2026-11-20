extends GdUnitTestSuite
## A street leads from the road into the city: levelled ground from the road's height to the
## city's, gentle enough to drive, drawn with its surface where you stand on it.

const WORLD := "res://modules/world/scenes/world.tscn"
const MODULE := "res://modules/city/city_module.gd"
## Steepest grade a car takes without trouble (about 17 degrees).
const DRIVABLE := 0.3

var _world: Node3D
var _voxels: VoxelWorld
var _city: Node


func before_test() -> void:
	_world = await VoxelWorld.add_and_wait(self, WORLD)
	_voxels = _world.get_node("Terrain")
	_city = (load(MODULE) as GDScript).new()
	add_child(_city)
	EventBus.publish(&"world.ready", {"spawn": Vector3.ZERO})


func after_test() -> void:
	_city.free()
	_world.free()


func test_a_street_leads_from_the_road_to_the_city_at_a_drivable_grade() -> void:
	var site: CitySite = _city.get(&"site")
	var approach: Dictionary = site.approach
	assert_bool(approach.is_empty()).is_false()
	var x := float(approach["x"])
	var z0 := float(approach["road"])
	var z1 := float(approach["to"])
	var start := site.global_transform * Vector3(x, 0.0, z0)
	assert_float(float(approach["from"])).is_between(z0, z1)
	# Starts on the road: the ground there is the road's.
	assert_float(_voxels.surface_height(start.x, start.z)).is_equal_approx(_voxels.ground_height(start.x, start.z), 0.05)
	# Up the middle and both lanes: the road band it leaves tilts as the road climbs.
	var lane := float(approach["width"]) / 2.0 - 1.0
	for across: float in [-lane, 0.0, lane]:
		var first := site.global_transform * Vector3(x + across, 0.0, z0)
		var last := _voxels.surface_height(first.x, first.z)
		var z := z0
		while z < z1 + 8.0:
			z += 0.5
			var p := site.global_transform * Vector3(x + across, 0.0, z)
			var h := _voxels.surface_height(p.x, p.z)
			assert_float(absf(h - last) / 0.5).override_failure_message("too steep %.1f m along, %.1f m across" % [z - z0, across]).is_less_equal(DRIVABLE)
			last = h
	# Ends level with the city's streets.
	var end := site.global_transform * Vector3(x, 0.0, z1 + 4.0)
	assert_float(_voxels.surface_height(end.x, end.z)).is_equal_approx(site.global_position.y, 0.02)


func test_streets_are_drawn_where_you_stand() -> void:
	# A street piece's asphalt top is the city's level, where the ground under it is.
	var where := CitySite.street_transform(Rect2(-4, -20, 8, 40), false)
	assert_float(where.origin.y + VoxRoad.BED + VoxRoad.SURFACE).is_equal_approx(0.0, 0.001)
	# The approach slopes the same way: its top runs from `drop` at the road to 0 at the city.
	var ramp := CitySite.approach_transform(0.0, -100.0, -75.0, 2.0)
	var half_length := Vector2(25, 2).length() / 2.0
	var road_end := ramp * Vector3(0, VoxRoad.BED + VoxRoad.SURFACE, -half_length)
	var city_end := ramp * Vector3(0, VoxRoad.BED + VoxRoad.SURFACE, half_length)
	assert_float(road_end.y).is_equal_approx(2.0, 0.01)
	assert_float(road_end.z).is_equal_approx(-100.0, 0.01)
	assert_float(city_end.y).is_equal_approx(0.0, 0.01)
	assert_float(city_end.z).is_equal_approx(-75.0, 0.01)
