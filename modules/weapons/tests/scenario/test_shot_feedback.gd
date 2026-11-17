extends GdUnitTestSuite
## The shooter's HUD: hits on you show an arc toward where the shot came from, the
## magazine turns to the warning colour when low, and all of it hides while you are dead.

const PLAYER := "res://modules/player/scenes/player.tscn"
const MODULE := "res://modules/weapons/weapons_module.gd"

var _player: PlayerController
var _feedback: ShotFeedback


func before_test() -> void:
	add_child(auto_free((load(MODULE) as GDScript).new()))
	_player = auto_free((load(PLAYER) as PackedScene).instantiate())
	add_child(_player)
	EventBus.publish(&"player.spawned", {"player": _player, "local": false})
	_feedback = auto_free(ShotFeedback.new())
	_feedback.local_player = _player
	add_child(_feedback)


func test_a_shot_from_the_left_draws_an_arc_on_the_left() -> void:
	var left := _player.global_position - _player.global_basis.x * 10.0
	EventBus.publish(&"weapon.fired", {"weapon": null, "holder": null, "from": left, "to": _player.global_position, "target": _player, "damage": 10.0})
	assert_int(_feedback.arcs().size()).is_equal(1)
	assert_float(float(_feedback.arcs()[0]["angle"])).is_equal_approx(-PI / 2.0, 0.01)
	_feedback._process_tick(ShotFeedback.DAMAGE_ARC_SECONDS + 0.1)
	assert_int(_feedback.arcs().size()).is_equal(0)


func test_a_shot_from_ahead_is_angle_zero() -> void:
	var ahead := _player.global_position - _player.global_basis.z * 10.0
	assert_float(_feedback.angle_to(ahead)).is_equal_approx(0.0, 0.01)


func test_misses_and_other_targets_draw_nothing() -> void:
	EventBus.publish(&"weapon.fired", {"weapon": null, "holder": null, "from": Vector3.ZERO, "to": Vector3.ONE, "target": null, "damage": 10.0})
	assert_int(_feedback.arcs().size()).is_equal(0)


func test_low_magazine_is_flagged() -> void:
	_feedback._process_tick(0.0)
	var weapon := _feedback._carried()
	assert_object(weapon).is_not_null()
	assert_bool(_feedback.is_low()).is_false()
	var size := _feedback.magazine_size()
	assert_int(size).is_greater(0)
	while weapon.ammo() > int(size * ShotFeedback.LOW_AMMO_SHARE):
		weapon.rules.try_fire()
		weapon.rules.tick(1.0)
	assert_bool(_feedback.is_low()).is_true()


func test_dead_hides_the_hud() -> void:
	EventBus.publish(&"player.died", {"player": _player})
	_feedback._process_tick(0.0)
	assert_bool((_feedback.get_child(0) as Control).visible).is_false()
	EventBus.publish(&"player.respawned", {"player": _player})
	_feedback._process_tick(0.0)
	assert_bool((_feedback.get_child(0) as Control).visible).is_true()
