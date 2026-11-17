extends GdUnitTestSuite
## Hand-made city blocks are data: every block file loads and checks out, a broken one is
## refused with its name, and a block picks the plots it fits.


func test_every_block_file_loads_and_checks_out() -> void:
	var names := CityBlock.names()
	assert_int(names.size()).is_greater_equal(3)
	for n in names:
		var block := CityBlock.load_named(n)
		assert_object(block).override_failure_message("block %s" % n).is_not_null()
		assert_int(block.pieces.size()).is_greater(0)


func test_a_broken_block_is_refused_with_its_name() -> void:
	var bad := {"name": "broken", "size": [30, 30], "tags": [], "pieces": [{"generator": "NoSuchThing", "params": {}, "at": [0, 0, 0], "yaw": 0}]}
	Log.begin_capture()
	var block := CityBlock.from_data(bad, "broken")
	var entries := Log.end_capture()
	assert_object(block).is_null()
	assert_str(LogCapture.text(entries)).contains("broken")
	var wrong_param := {"name": "wrong", "size": [30, 30], "tags": [], "pieces": [{"generator": "VoxShed", "params": {"no_such_param": 1}, "at": [0, 0, 0], "yaw": 0}]}
	Log.begin_capture()
	assert_object(CityBlock.from_data(wrong_param, "wrong")).is_null()
	assert_str(LogCapture.text(Log.end_capture())).contains("no_such_param")


func test_a_block_fits_plots_near_its_size() -> void:
	var block := CityBlock.from_data({"name": "t", "size": [30, 28], "tags": ["market"], "pieces": [{"generator": "VoxBarrel", "params": {}, "at": [0, 0, 0], "yaw": 0}]}, "t")
	assert_bool(block.fits(Vector2(31, 28.5), 2.0)).is_true()
	assert_bool(block.fits(Vector2(36, 28), 2.0)).is_false()
	assert_bool(block.has_tag("market")).is_true()


func test_it_round_trips_through_its_data() -> void:
	for n in CityBlock.names():
		var block := CityBlock.load_named(n)
		var again := CityBlock.from_data(block.to_data(), n)
		assert_str(JSON.stringify(again.to_data())).is_equal(JSON.stringify(block.to_data()))
