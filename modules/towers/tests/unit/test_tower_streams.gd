extends GdUnitTestSuite
## A holed tank leaks: its jets fall close to the tank instead of shooting metres out like a
## fire hose (playtest 2, #410).

const CONFIG := "res://modules/towers/data/towers.json"


func test_a_full_tank_jet_lands_close_to_the_tank() -> void:
	var tower: Dictionary = (Data.load_json(CONFIG) as Dictionary)["tower"]
	var depth := float(tower["tank"]) * float(tower["fill"])
	var speed := WaterTower.stream_speed(depth, float(tower["stream_speed_share"]))
	# From the bottom of a full tank, the deepest water and the longest fall.
	var out := WaterTower.throw_distance(float(tower["height"]), speed)
	assert_float(out).is_less_equal(2.0)
	assert_float(out).is_greater(0.5)


func test_fewer_and_thinner_jets_than_a_burst_main() -> void:
	var tower: Dictionary = (Data.load_json(CONFIG) as Dictionary)["tower"]
	assert_int(int(tower["max_holes"])).is_less_equal(10)
	assert_int(int(tower["stream_drops"])).is_less_equal(120)
