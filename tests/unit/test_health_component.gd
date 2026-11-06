extends GdUnitTestSuite

var _health: HealthComponent
var _died_count := 0


func before_test() -> void:
	_health = auto_free(HealthComponent.new())
	_health.max_health = 100.0
	add_child(_health)
	_died_count = 0
	_health.died.connect(func(_s: Node) -> void: _died_count += 1)


func test_starts_full() -> void:
	assert_float(_health.health).is_equal(100.0)


func test_damage_reduces_health_and_reports_dealt() -> void:
	assert_float(_health.server_apply_damage(30.0)).is_equal(30.0)
	assert_float(_health.health).is_equal(70.0)


func test_overkill_clamps_and_dies_once() -> void:
	assert_float(_health.server_apply_damage(250.0)).is_equal(100.0)
	_health.server_apply_damage(10.0)
	assert_bool(_health.is_dead()).is_true()
	assert_int(_died_count).is_equal(1)


func test_reset_restores_full_health() -> void:
	_health.server_apply_damage(100.0)
	_health.server_reset()
	assert_float(_health.health).is_equal(100.0)
	assert_bool(_health.is_dead()).is_false()


func test_found_from_a_child_collider() -> void:
	var entity: Node3D = auto_free(Node3D.new())
	var hp := HealthComponent.new()
	entity.add_child(hp)
	var body := StaticBody3D.new()
	entity.add_child(body)
	assert_object(HealthComponent.find_on(body)).is_same(hp)
