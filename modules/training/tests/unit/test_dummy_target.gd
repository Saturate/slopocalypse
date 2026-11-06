extends GdUnitTestSuite

const SCENE := "res://modules/training/scenes/dummy.tscn"

var _dummy: DummyTarget


func before_test() -> void:
	_dummy = auto_free((load(SCENE) as PackedScene).instantiate())
	add_child(_dummy)


func test_starts_at_full_health_from_data() -> void:
	var data: Dictionary = Data.load_json("res://modules/training/data/training.json")
	assert_float(_dummy.health().health).is_equal(data["max_health"])


func test_goes_down_at_zero_and_stands_back_up() -> void:
	_dummy.health().server_apply_damage(1000.0)
	assert_bool(_dummy.is_down()).is_true()
	var wait := int(ceil(_dummy.respawn_seconds * Engine.physics_ticks_per_second)) + 5
	for i in wait:
		await get_tree().physics_frame
	assert_bool(_dummy.is_down()).is_false()
	assert_float(_dummy.health().health).is_equal(_dummy.health().max_health)
