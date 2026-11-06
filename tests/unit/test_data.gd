extends GdUnitTestSuite

const FIX := "res://tests/fixtures/data/"
const RIFLE_FIELDS := {"name": TYPE_STRING, "damage": TYPE_FLOAT}


func before_test() -> void:
	Log.begin_capture()


func after_test() -> void:
	Log.end_capture()


func _messages() -> String:
	var lines: PackedStringArray = []
	for e: Dictionary in Log.end_capture():
		lines.append(e["message"])
	return "\n".join(lines)


func test_loads_and_validates_good_file() -> void:
	var data: Variant = Data.load_json(FIX + "good.json")
	assert_bool(data is Dictionary).is_true()
	var dict: Dictionary = data
	assert_bool(Data.require(FIX + "good.json", dict, RIFLE_FIELDS)).is_true()
	assert_float(dict["damage"]).is_equal(25.0)
	assert_str(_messages()).is_empty()


func test_missing_file_fails_loudly() -> void:
	assert_object(Data.load_json(FIX + "nope.json")).is_null()
	assert_str(_messages()).contains("nope.json").contains("not found")


func test_bad_json_names_file_and_line() -> void:
	assert_object(Data.load_json(FIX + "bad_syntax.json")).is_null()
	assert_str(_messages()).contains("bad_syntax.json").contains("line 3")


func test_root_must_be_an_object() -> void:
	assert_object(Data.load_json(FIX + "not_object.json")).is_null()
	assert_str(_messages()).contains("not_object.json").contains("object")


func test_missing_field_names_file_and_field() -> void:
	var dict: Dictionary = Data.load_json(FIX + "missing_field.json")
	assert_bool(Data.require(FIX + "missing_field.json", dict, RIFLE_FIELDS)).is_false()
	assert_str(_messages()).contains("missing_field.json").contains("'damage'")


func test_wrong_type_names_field_and_types() -> void:
	var dict: Dictionary = Data.load_json(FIX + "wrong_type.json")
	assert_bool(Data.require(FIX + "wrong_type.json", dict, RIFLE_FIELDS)).is_false()
	assert_str(_messages()).contains("'damage'").contains("float").contains("String")
