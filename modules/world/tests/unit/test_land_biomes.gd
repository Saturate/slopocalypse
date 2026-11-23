extends GdUnitTestSuite
## Biomes on the land (#427): broken rock where it is steep, forest leaning to hilly country and
## never in water, open ground on the flat lowland.

const GRASSLAND := "res://modules/world/data/maps/grassland.json"


func _recipe() -> Dictionary:
	return Data.load_json(GRASSLAND)


## Points of the map, every `step` metres.
func _points(land: WorldLand, step: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var b := land.bounds()
	var x := b.position.x + step / 2.0
	while x < b.end.x:
		var z := b.position.y + step / 2.0
		while z < b.end.y:
			out.append(Vector2(x, z))
			z += step
		x += step
	return out


func test_steep_ground_is_rock_and_flat_lowland_is_not() -> void:
	var recipe := _recipe()
	var walk: Dictionary = recipe["walkable"]
	var land := WorldLand.new(recipe, 7)
	var steep_rock := 0.0
	var steep := 0
	var flat_rock := 0.0
	var flat := 0
	for p in _points(land, 24.0):
		var grade := land.grade(p.x, p.y)
		# Rock belongs to steep ground in the heart of the hills.
		if grade > float(recipe["biomes"]["rock_grade_to"]) and land.hilliness(p.x, p.y) > 0.9:
			steep_rock += land.rock(p.x, p.y)
			steep += 1
		elif grade < float(walk["flat_grade"]) and land.hilliness(p.x, p.y) < 0.1:
			flat_rock += land.rock(p.x, p.y)
			flat += 1
	assert_int(steep).is_greater(0)
	# Steep ground is broken rock (outcrops and scree in patches), the flat lowland meadow.
	assert_float(steep_rock / steep).is_greater(0.15)
	assert_float(steep_rock / steep).is_greater(2.0 * flat_rock / flat)
	assert_float(flat_rock / flat).is_less(0.3)


func test_forest_leans_to_the_hills_and_stays_out_of_water() -> void:
	var land := WorldLand.new(_recipe(), 3)
	var hill_forest := 0.0
	var hills := 0
	var low_forest := 0.0
	var lows := 0
	for p in _points(land, 24.0):
		if not is_nan(land.water_level(p.x, p.y)):
			assert_float(land.forest(p.x, p.y)).is_equal(0.0)
			continue
		if land.hilliness(p.x, p.y) > 0.8:
			hill_forest += land.forest(p.x, p.y)
			hills += 1
		elif land.hilliness(p.x, p.y) < 0.05:
			low_forest += land.forest(p.x, p.y)
			lows += 1
	assert_float(hill_forest / hills).is_greater(low_forest / lows)


func test_the_same_seed_gives_the_same_biomes() -> void:
	var a := WorldLand.new(_recipe(), 11)
	var b := WorldLand.new(_recipe(), 11)
	for p in _points(a, 200.0):
		assert_float(a.forest(p.x, p.y)).is_equal(b.forest(p.x, p.y))
		assert_float(a.dry(p.x, p.y)).is_equal(b.dry(p.x, p.y))
		assert_float(a.rock(p.x, p.y)).is_equal(b.rock(p.x, p.y))
