extends GdUnitTestSuite
## How far a place is from people (#419), from the world's data.

const WORLD := "res://modules/world/data/world.json"
const CITY := "res://modules/city/data/city.json"

var _r: Remoteness
var _cfg: Dictionary


func before() -> void:
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(WORLD))
	_cfg = world["remoteness"]
	_r = Remoteness.new(_cfg)


func _along(name: String) -> float:
	for s: Dictionary in _cfg["settlements"]:
		if s["name"] == name:
			return float(s["along"])
	return NAN


func test_it_is_zero_in_the_camp_and_the_city() -> void:
	assert_float(_r.at(_along("camp"))).is_equal(0.0)
	assert_float(_r.at(_along("city"))).is_equal(0.0)


func test_it_rises_down_the_road_away_from_both_and_never_passes_one() -> void:
	var last := 0.0
	var along := _along("city")
	while along < 4000.0:
		var r := _r.at(along)
		assert_float(r).is_greater_equal(last).is_less_equal(1.0)
		last = r
		along += 25.0
	assert_float(last).is_equal(1.0)


func test_it_rises_faster_off_the_road_than_along_it() -> void:
	var along := _along("city") + 600.0
	assert_float(_r.at(along, 50.0) - _r.at(along)).is_greater(_r.at(along + 50.0) - _r.at(along))


func test_the_road_near_the_city_has_fewer_potholes_than_the_far_end() -> void:
	assert_int(_r.road_potholes(_along("city"))).is_less(_r.road_potholes(3000.0))
	assert_float(_r.road_wear(_along("city"))).is_less(_r.road_wear(3000.0))


func test_the_city_settlement_matches_where_the_city_module_puts_it() -> void:
	var city: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CITY))
	var half := float(city["size"]) / 2.0
	assert_float(_along("city")).is_equal_approx(float(city["at"]) + half, 0.5)
	var radius := 0.0
	for s: Dictionary in _cfg["settlements"]:
		if s["name"] == "city":
			radius = float(s["radius"])
	assert_float(radius).is_greater_equal(half)
