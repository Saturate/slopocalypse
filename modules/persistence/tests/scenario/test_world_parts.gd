extends GdUnitTestSuite
## World damage survives a restart: every module in the `world_state` group hands
## persistence its part, and gets the same part back on the next load. Lights and towers
## put back what they saved. Runs on an in-memory save.

const PERSISTENCE := "res://modules/persistence/persistence_module.gd"
const LIGHTS := "res://modules/lights/lights_module.gd"
const TOWERS := "res://modules/towers/towers_module.gd"


## A module with some damage to keep.
class Keeper extends Node:
	var state: Variant = {"craters": [Vector4(1, 2, 3, 4)], "count": 3}
	var restored: Variant = null
	var restored_version := -1

	func _ready() -> void:
		add_to_group(&"world_state")

	func world_state_owner() -> String:
		return "keeper"

	func world_state_version() -> int:
		return 2

	func server_world_state() -> Variant:
		return state

	func server_restore_world_state(version: int, data: Variant) -> void:
		restored_version = version
		restored = data


var _saves: Node


func before_test() -> void:
	_saves = auto_free((load(PERSISTENCE) as GDScript).new())
	_saves.set(&"enabled", false)
	add_child(_saves)
	assert_bool(_saves.call(&"start", ":memory:")).is_true()


func test_each_part_comes_back_to_its_owner_with_its_version() -> void:
	var keeper: Keeper = auto_free(Keeper.new())
	add_child(keeper)
	assert_bool(_saves.call(&"server_save_parts")).is_true()
	keeper.state = {}
	_saves.call(&"server_load_parts")
	assert_int(keeper.restored_version).is_equal(2)
	assert_that(keeper.restored).is_equal({"craters": [Vector4(1, 2, 3, 4)], "count": 3})


func test_nothing_saved_means_nothing_restored() -> void:
	var keeper: Keeper = auto_free(Keeper.new())
	add_child(keeper)
	_saves.call(&"server_load_parts")
	assert_int(keeper.restored_version).is_equal(-1)


func test_shot_out_lamps_stay_out() -> void:
	var lights: Node = auto_free((load(LIGHTS) as GDScript).new())
	add_child(lights)
	lights.call(&"place", [Transform3D.IDENTITY, Transform3D(Basis.IDENTITY, Vector3(0, 0, -30))] as Array[Transform3D])
	EventBus.publish(&"lights.lamp_broken", {"id": 1})
	assert_bool(_saves.call(&"server_save_parts")).is_true()
	# A fresh server: lamps placed again, then the save is read.
	lights.free()
	var again: Node = auto_free((load(LIGHTS) as GDScript).new())
	add_child(again)
	again.call(&"place", [Transform3D.IDENTITY, Transform3D(Basis.IDENTITY, Vector3(0, 0, -30))] as Array[Transform3D])
	_saves.call(&"server_load_parts")
	var lamps: Array = again.get(&"lamps")
	assert_bool((lamps[0] as StreetLamp).broken).is_false()
	assert_bool((lamps[1] as StreetLamp).broken).is_true()


func test_holed_towers_stay_holed() -> void:
	var towers: Node = auto_free((load(TOWERS) as GDScript).new())
	add_child(towers)
	towers.call(&"place", [Transform3D.IDENTITY] as Array[Transform3D])
	var t: WaterTower = (towers.get(&"towers") as Array)[0]
	var hole := t.tank_hit(t.global_transform * Vector3(float(t.config["radius"]), float(t.config["height"]) + 0.4, 0.0))
	EventBus.publish(&"towers.holed", {"id": 0, "point": hole["point"], "normal": hole["normal"]})
	for i in 120:
		t.tank.advance(1.0 / 60.0)
	var level := t.level()
	assert_bool(_saves.call(&"server_save_parts")).is_true()
	towers.free()
	var again: Node = auto_free((load(TOWERS) as GDScript).new())
	add_child(again)
	again.call(&"place", [Transform3D.IDENTITY] as Array[Transform3D])
	_saves.call(&"server_load_parts")
	var copy: WaterTower = (again.get(&"towers") as Array)[0]
	assert_float(copy.level()).is_equal_approx(level, 0.02)
	assert_int(copy.tank.pouring().size()).is_equal(1)
