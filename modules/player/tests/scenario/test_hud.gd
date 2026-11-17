extends GdUnitTestSuite
## The minimal HUD: health fades back when full and quiet, comes back on a hit, pulses red
## at the edges while low, and the death screen replaces it.

const PLAYER := "res://modules/player/scenes/player.tscn"

var _player: PlayerController
var _hud: PlayerHud
var _health: HealthComponent


func before_test() -> void:
	_player = auto_free((load(PLAYER) as PackedScene).instantiate())
	add_child(_player)
	_health = _player.get_node("Health") as HealthComponent
	_hud = PlayerHud.new()
	_hud.player = _player
	_player.add_child(_hud)


func _run(seconds: float) -> void:
	var step := 1.0 / 30.0
	var t := 0.0
	while t < seconds:
		_hud._process_tick(step)
		t += step


func test_full_health_fades_after_a_quiet_while_and_returns_on_a_hit() -> void:
	_run(PlayerHud.QUIET_SECONDS + 2.0)
	assert_bool(_hud.is_faded()).is_true()
	_health.server_apply_damage(10.0, null)
	_run(0.5)
	assert_bool(_hud.is_faded()).is_false()


func test_low_health_glows_at_the_edges_and_full_does_not() -> void:
	_run(0.5)
	assert_float(_hud.edge_strength()).is_equal(0.0)
	_health.server_apply_damage(_health.max_health * 0.85, null)
	_run(PlayerHud.FLASH_SECONDS + 0.1)
	assert_float(_hud.edge_strength()).is_greater(0.0)


func test_death_hides_the_readout() -> void:
	EventBus.publish(&"player.died", {"player": _player})
	_run(0.2)
	var number := _hud.get_child(0).get_child(0) as Label
	assert_bool(number.visible).is_false()
	EventBus.publish(&"player.respawned", {"player": _player})
	_run(0.2)
	assert_bool(number.visible).is_true()
