extends GdUnitTestSuite
## Headshots: a guard hit in the head dies on the spot (no helmets yet); a body shot does
## the gun's damage. Between players a headshot only multiplies the damage.

const PLAYER := "res://modules/player/scenes/player.tscn"
const RIFLE := "res://modules/weapons/scenes/rifle.tscn"

var _ground: StaticBody3D
var _shooter: PlayerController
var _rifle: HitscanWeapon
var _guard: PlayerController


func before_test() -> void:
	_ground = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100.0, 1.0, 100.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	_ground.add_child(shape)
	add_child(_ground)
	_shooter = (load(PLAYER) as PackedScene).instantiate()
	add_child(_shooter)
	_rifle = (load(RIFLE) as PackedScene).instantiate()
	_rifle.holder = _shooter
	_shooter.get_node("Head/Camera").add_child(_rifle)
	_guard = (load(PLAYER) as PackedScene).instantiate()
	_guard.set_meta(&"team", "enemies")
	add_child(_guard)
	_guard.global_position = Vector3(0.0, 0.0, -6.0)
	# Both stand still for the test; physics would let them settle and drift.
	_shooter.set_physics_process(false)
	_guard.set_physics_process(false)


func after_test() -> void:
	_shooter.free()
	_guard.free()
	_ground.free()


## Fired from inside a physics step, like in play: the bodies placed in before_test are only
## in the physics world's queries from then on.
func _shoot_at(point: Vector3) -> void:
	for i in 3:
		await get_tree().physics_frame
	var origin := (_shooter.get_node("Head") as Node3D).global_position
	_rifle.server_fire(origin, (point - origin).normalized())


func test_a_headshot_kills_a_guard_outright() -> void:
	var health := _guard.get_node("Health") as HealthComponent
	await _shoot_at((_guard.get_node("Head") as Node3D).global_position)
	assert_float(health.health).is_equal(0.0)


func test_a_body_shot_does_the_guns_damage() -> void:
	var health := _guard.get_node("Health") as HealthComponent
	await _shoot_at(_guard.global_position + Vector3.UP * 1.0)
	assert_float(health.health).is_greater(0.0)
	assert_float(health.health).is_less(health.max_health)


func test_only_points_near_the_eyes_count_as_the_head() -> void:
	var head := (_guard.get_node("Head") as Node3D).global_position
	assert_bool(HitscanWeapon.is_headshot(_guard, head + Vector3.UP * 0.1)).is_true()
	assert_bool(HitscanWeapon.is_headshot(_guard, head + Vector3.DOWN * 0.6)).is_false()
