extends GdUnitTestSuite
## Each map recipe gives the land it promises (#427): its own walkable, flat and hillside
## shares on every seed, and recipes differ.

const RECIPES := ["res://modules/world/data/maps/grassland.json", "res://modules/world/data/maps/mixed.json"]
const SURVEY := 16.0


func test_every_recipe_keeps_its_promises_on_every_seed() -> void:
	for path: String in RECIPES:
		var recipe: Dictionary = Data.load_json(path)
		var walk: Dictionary = recipe["walkable"]
		for seed_value in 10:
			var land := WorldLand.new(recipe, seed_value)
			var where := "%s seed %d" % [path.get_file(), seed_value]
			assert_float(land.walkable_share(SURVEY, float(walk["max_grade"]))).override_failure_message(where + ": too steep").is_greater_equal(float(walk["min_share"]))
			assert_float(land.walkable_share(SURVEY, float(walk["flat_grade"]))).override_failure_message(where + ": too little flat").is_greater_equal(float(walk["min_flat_share"]))
			assert_float(1.0 - land.walkable_share(SURVEY, float(walk["hillside_grade"]))).override_failure_message(where + ": too few hillsides").is_greater_equal(float(walk["min_hillside_share"]))


func test_mixed_country_is_hillier_than_grassland() -> void:
	var grass := WorldLand.new(Data.load_json(RECIPES[0]), 4)
	var mixed := WorldLand.new(Data.load_json(RECIPES[1]), 4)
	assert_float(mixed.walkable_share(SURVEY, 0.2)).is_less(grass.walkable_share(SURVEY, 0.2))
