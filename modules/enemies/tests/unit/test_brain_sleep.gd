extends GdUnitTestSuite
## When a soldier or civilian far from players sleeps, and that nobody a client is sent sleeps.


func test_sleeps_past_the_distance_plus_margin_and_wakes_inside_the_distance() -> void:
	# Awake: keeps going until past distance + margin.
	assert_bool(BrainSleep.sleeps(false, 390.0, 360.0, 40.0)).is_false()
	assert_bool(BrainSleep.sleeps(false, 410.0, 360.0, 40.0)).is_true()
	# Asleep: stays so until inside the distance.
	assert_bool(BrainSleep.sleeps(true, 380.0, 360.0, 40.0)).is_true()
	assert_bool(BrainSleep.sleeps(true, 350.0, 360.0, 40.0)).is_false()


func test_everyone_sleeps_with_nobody_connected() -> void:
	assert_bool(BrainSleep.sleeps(false, INF, 360.0, 40.0)).is_true()


func test_nobody_a_client_is_sent_is_asleep() -> void:
	var sleep: Dictionary = (Data.load_json("res://modules/enemies/data/enemies.json") as Dictionary)["sleep"]
	var net: Dictionary = Data.load_json("res://data/net.json")
	assert_float(float(sleep["distance"])).is_greater_equal(float(net["relevance_distance"]) + float(net["relevance_margin"]))
