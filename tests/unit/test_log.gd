extends GdUnitTestSuite


func after_test() -> void:
	Log.end_capture()


func test_capture_records_errors_and_warnings_instead_of_pushing() -> void:
	Log.begin_capture()
	Log.error(&"data", "broken file")
	Log.warn(&"net", "slow peer")
	Log.info(&"boot", "not captured")
	var entries: Array[Dictionary] = Log.end_capture()
	assert_int(entries.size()).is_equal(2)
	assert_str(entries[0]["message"]).is_equal("broken file")
	assert_str(String(entries[0]["category"])).is_equal("data")
	assert_int(entries[0]["level"]).is_equal(Log.Level.ERROR)


func test_end_capture_clears_entries() -> void:
	Log.begin_capture()
	Log.error(&"x", "once")
	Log.end_capture()
	Log.begin_capture()
	assert_int(Log.end_capture().size()).is_equal(0)
