extends GdUnitTestSuite


func test_engine_is_pinned_version() -> void:
	var info: Dictionary = Engine.get_version_info()
	assert_int(info["major"]).is_equal(4)
	assert_int(info["minor"]).is_equal(7)
	assert_int(info["patch"]).is_equal(2)
