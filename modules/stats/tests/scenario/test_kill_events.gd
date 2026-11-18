extends GdUnitTestSuite
## The server counts kills from the death events: a soldier (with its faction), another
## player, a drone; the victim's death by cause; a headshot; and a charge counts for whoever
## threw it (the charge names its thrower as the source).

const STATS := "res://modules/stats/stats_module.gd"
const PLAYER := "res://modules/player/scenes/player.tscn"

var _stats: Node


func before_test() -> void:
	_stats = auto_free((load(STATS) as GDScript).new())
	add_child(_stats)


func _player(peer: int, at := Vector3.ZERO) -> PlayerController:
	var p: PlayerController = auto_free((load(PLAYER) as PackedScene).instantiate())
	p.set_meta(&"peer_id", peer)
	p.add_to_group(&"players")
	add_child(p)
	p.set_physics_process(false)
	p.global_position = at
	return p


func _soldier(faction: String) -> Node3D:
	var s: Node3D = auto_free(Node3D.new())
	s.set_meta(&"faction", faction)
	s.add_to_group(&"enemies")
	add_child(s)
	return s


func _count(peer: int, key: String) -> float:
	return float((_stats.call(&"server_stats_of", peer) as Dictionary).get(key, 0.0))


func test_a_soldier_kill_counts_with_its_faction_and_distance() -> void:
	var me := _player(81)
	EventBus.publish(&"enemy.died", {"enemy": _soldier("militia"), "source": me, "position": Vector3(0, 0, -150)})
	assert_float(_count(81, "kills.soldier")).is_equal(1.0)
	assert_float(_count(81, "kills.soldier.militia")).is_equal(1.0)
	assert_float(_count(81, "longest_kill")).is_equal_approx(150.0, 0.5)


func test_killing_a_player_counts_for_both() -> void:
	var me := _player(82)
	var them := _player(83, Vector3(10, 0, 0))
	EventBus.publish(&"player.died", {"player": them, "source": me, "position": them.global_position})
	assert_float(_count(82, "kills.player")).is_equal(1.0)
	assert_float(_count(83, "deaths")).is_equal(1.0)
	assert_float(_count(83, "deaths.player")).is_equal(1.0)


func test_dying_to_a_soldier_or_yourself_counts_as_such() -> void:
	var me := _player(84)
	EventBus.publish(&"player.died", {"player": me, "source": _soldier("regulars"), "position": Vector3.ZERO})
	EventBus.publish(&"player.died", {"player": me, "source": me, "position": Vector3.ZERO})
	assert_float(_count(84, "deaths.soldier")).is_equal(1.0)
	assert_float(_count(84, "deaths.self")).is_equal(1.0)
	assert_float(_count(84, "kills.player")).is_equal(0.0)


func test_a_drone_and_a_headshot_count() -> void:
	var me := _player(85)
	var drone: Node3D = auto_free(Node3D.new())
	add_child(drone)
	EventBus.publish(&"drone.died", {"drone": drone, "source": me})
	EventBus.publish(&"weapon.headshot_kill", {"holder": me, "target": drone})
	assert_float(_count(85, "kills.drone")).is_equal(1.0)
	assert_float(_count(85, "headshots")).is_equal(1.0)


func test_a_thrown_charge_counts_for_its_thrower() -> void:
	# A charge's blast names its thrower as the damage source, so the death does too.
	var thrower := _player(86)
	EventBus.publish(&"enemy.died", {"enemy": _soldier("scavengers"), "source": thrower, "position": Vector3(0, 0, -8)})
	assert_float(_count(86, "kills.soldier.scavengers")).is_equal(1.0)
