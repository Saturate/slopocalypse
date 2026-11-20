extends GdUnitTestSuite
## The land from a map recipe (#427, decision 0010): the same recipe and seed give the same
## heights on every machine, and most of it is gentle enough to walk.

const GRASSLAND := "res://modules/world/data/maps/grassland.json"
## Metres between samples when surveying a whole map.
const SURVEY := 16.0


func _recipe() -> Dictionary:
	return Data.load_json(GRASSLAND)


func _grid_hash(land: WorldLand) -> int:
	var b := land.bounds()
	var values := PackedFloat32Array()
	var x := b.position.x
	while x < b.end.x:
		var z := b.position.y
		while z < b.end.y:
			values.append(land.height(x, z))
			z += 64.0
		x += 64.0
	return hash(values)


func test_the_same_recipe_and_seed_give_the_same_land() -> void:
	var a := WorldLand.new(_recipe(), 7)
	var b := WorldLand.new(_recipe(), 7)
	var c := WorldLand.new(_recipe(), 8)
	assert_int(_grid_hash(a)).is_equal(_grid_hash(b))
	assert_int(_grid_hash(a)).is_not_equal(_grid_hash(c))


func test_the_map_is_the_recipe_size_round_the_origin() -> void:
	var recipe := _recipe()
	var land := WorldLand.new(recipe, 1)
	var size := float(recipe["size"])
	assert_vector(land.bounds().size).is_equal(Vector2(size, size))
	assert_vector(land.bounds().get_center()).is_equal(Vector2.ZERO)


func test_most_of_it_is_gentle_enough_to_walk_on_every_seed() -> void:
	var recipe := _recipe()
	var grade := float(recipe["walkable"]["max_grade"])
	var wanted := float(recipe["walkable"]["min_share"])
	for seed_value in 20:
		var land := WorldLand.new(recipe, seed_value)
		var share := land.walkable_share(SURVEY, grade)
		assert_float(share).override_failure_message("seed %d: %.2f walkable" % [seed_value, share]).is_greater_equal(wanted)


func test_it_has_hills_not_a_plain() -> void:
	var recipe := _recipe()
	var land := WorldLand.new(recipe, 3)
	# Some of it steeper than an easy walk: ridges and hillsides, not a plain.
	assert_float(land.walkable_share(SURVEY, float(recipe["walkable"]["max_grade"]))).is_less(0.99)
	var low := INF
	var high := -INF
	var b := land.bounds()
	for i in 64:
		for j in 64:
			var h := land.height(b.position.x + b.size.x * i / 64.0, b.position.y + b.size.y * j / 64.0)
			low = minf(low, h)
			high = maxf(high, h)
	assert_float(high - low).is_greater(50.0)


func test_surveying_a_whole_map_is_quick() -> void:
	var land := WorldLand.new(_recipe(), 5)
	var start := Time.get_ticks_msec()
	land.walkable_share(8.0, 0.35)
	# 2 km at 8 m is about 65 000 samples; later stages survey it a few times at load.
	assert_int(Time.get_ticks_msec() - start).is_less(1500)
