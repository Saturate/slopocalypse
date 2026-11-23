extends GdUnitTestSuite
## The suppression value's rules and the near-miss distance, and that every value is read
## from the data file.

const CONFIG := "res://modules/suppression/data/suppression.json"


func test_near_misses_add_up_to_at_most_one_and_decay_to_zero() -> void:
	var level := SuppressionLevel.new()
	level.per_near_miss = 0.3
	level.decay_per_second = 0.5
	level.add_near_miss()
	level.add_near_miss()
	assert_float(level.value).is_equal_approx(0.6, 0.0001)
	for i in 5:
		level.add_near_miss()
	assert_float(level.value).is_equal(1.0)
	level.tick(1.0)
	assert_float(level.value).is_equal_approx(0.5, 0.0001)
	level.tick(5.0)
	assert_float(level.value).is_equal(0.0)


func test_values_come_from_the_data() -> void:
	var data: Dictionary = Data.load_json(CONFIG)
	data = data.duplicate(true)
	data["per_near_miss"] = 0.4
	data["decay_per_second"] = 0.1
	var level := SuppressionLevel.from_config(data)
	level.add_near_miss()
	assert_float(level.value).is_equal_approx(0.4, 0.0001)
	level.tick(1.0)
	assert_float(level.value).is_equal_approx(0.3, 0.0001)


func test_distance_to_a_round_path() -> void:
	var a := Vector3(0, 1, -50)
	var b := Vector3(0, 1, 50)
	assert_float(SuppressionLevel.distance_to_segment(Vector3(1.5, 1, 0), a, b)).is_equal_approx(1.5, 0.0001)
	# Past the end of the path (the round stopped in a wall short of you) counts from the end.
	assert_float(SuppressionLevel.distance_to_segment(Vector3(0, 1, 53), a, b)).is_equal_approx(3.0, 0.0001)
	assert_vector(SuppressionLevel.closest_on_segment(Vector3(1.5, 1, 4), a, b)).is_equal_approx(Vector3(0, 1, 4), Vector3.ONE * 0.0001)
