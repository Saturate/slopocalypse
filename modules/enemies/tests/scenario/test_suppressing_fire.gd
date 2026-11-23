extends GdUnitTestSuite
## A squad's gunner (real body, real machine gun, brain) fighting a player who ducks out of
## sight keeps firing at where it last saw them for `suppress.seconds`, into the cover, wide
## on purpose, then stops; a rifleman in the same spot stops at once. Rounds still hurt a
## player who stays in the open, the gunner never fires into a wall right at its muzzle, and
## while it fires its squad mates move without taking turns. Same setup as
## test_enemy_fights.gd; brains think every 0.1 s, as near a player.

const PLAYER := "res://modules/player/scenes/player.tscn"
const ENEMIES := "res://modules/enemies/enemies_module.gd"
const WEAPONS := "res://modules/weapons/weapons_module.gd"
const INVENTORY := "res://modules/inventory/inventory_module.gd"
const THINK := 0.1

var _ground: StaticBody3D
var _enemies: Node
var _player: PlayerController
## Shots fired by soldiers: the `weapon.fired` payload plus `at`, physics seconds.
var _shots: Array[Dictionary] = []


func before_test() -> void:
	_ground = auto_free(StaticBody3D.new())
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	_ground.add_child(shape)
	add_child(_ground)
	add_child(auto_free((load(WEAPONS) as GDScript).new()))
	if ResourceLoader.exists(INVENTORY):
		add_child(auto_free((load(INVENTORY) as GDScript).new()))
	_enemies = auto_free((load(ENEMIES) as GDScript).new())
	add_child(_enemies)
	# Brave, so these are about the gun and not about fear.
	((_enemies.get(&"config") as Dictionary)["fortitude"] as Dictionary)["start"] = [20, 20]
	_player = auto_free((load(PLAYER) as PackedScene).instantiate())
	_player.set_meta(&"peer_id", 1)
	_player.add_to_group(&"players")
	add_child(_player)
	EventBus.publish(&"player.spawned", {"player": _player, "local": false})
	(_player.get_node("Health") as HealthComponent).invulnerable = true
	_shots.clear()
	EventBus.subscribe(&"weapon.fired", _on_fired)


func after_test() -> void:
	EventBus.unsubscribe(&"weapon.fired", _on_fired)


func _on_fired(p: Dictionary) -> void:
	var holder: Variant = p.get("holder")
	if bool(p.get("through", false)) or not holder is Node or not (holder as Node).is_in_group(&"enemies"):
		return
	var shot := p.duplicate()
	shot["at"] = _now()
	_shots.append(shot)


## Physics time: what the brain counts in, whatever the machine's load.
func _now() -> float:
	return float(Engine.get_physics_frames()) / float(Engine.physics_ticks_per_second)


## Waits `seconds` of physics time, which is what the brain counts in: on a loaded machine
## the physics ticks fall behind the clock.
func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, true).timeout


func _brain(enemy: PlayerController) -> EnemyBrain:
	return enemy.get_node("Brain") as EnemyBrain


## A soldier at `at` facing -Z, thinking every `THINK`; a gunner carries the machine gun.
func _soldier(at: Vector3, gunner: bool) -> PlayerController:
	var squad: Array[Node] = _enemies.call(&"server_spawn_squad", 1, at)
	await get_tree().process_frame
	var enemy := squad[0] as PlayerController
	enemy.global_position = at + Vector3.UP * 0.1
	var brain := _brain(enemy)
	brain.gunner = gunner
	brain.set_think_every(THINK)
	(brain.get(&"_rng") as RandomNumberGenerator).seed = 7
	if gunner:
		EventBus.publish(&"weapons.build_changed", {"peer": int(enemy.get_meta(&"peer_id")), "slot": "primary", "build": GunAssembly.build("mg_standard")})
	return enemy


## Swapping guns starts a reload and the machine gun is slow to draw: waits until it can
## fire, or a test of it not firing proves nothing.
func _loaded(enemy: PlayerController) -> void:
	var gun := enemy.get_node("Head/Camera/Weapon_primary") as HitscanWeapon
	var start := Time.get_ticks_msec()
	while (gun.is_reloading() or gun.ammo() == 0) and Time.get_ticks_msec() - start < 15000:
		await get_tree().physics_frame
	await _wait(1.2)
	assert_int(gun.ammo()).is_greater(0)


func _box(at: Vector3, size: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	wall.add_child(shape)
	add_child(auto_free(wall))
	wall.global_position = at
	return wall


## Waits (wall time, up to `limit` seconds) until `enemy` has fired on the player.
func _until_engaged(enemy: PlayerController, limit := 8.0) -> bool:
	var brain := _brain(enemy)
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < int(limit * 1000.0):
		if brain.get(&"_engaged_with") == _player and _shots.size() > 0:
			return true
		await get_tree().physics_frame
	return false


func _seconds() -> float:
	return float(((_enemies.get(&"config") as Dictionary)["suppress"] as Dictionary)["seconds"])


func _spread_degrees() -> float:
	return float(((_enemies.get(&"config") as Dictionary)["suppress"] as Dictionary)["spread_degrees"])


func _after(t: float) -> Array[Dictionary]:
	return _shots.filter(func(s: Dictionary) -> bool: return float(s["at"]) > t)


## The player 20 m ahead in the open is fought, then a wall goes up in front of them: they
## ducked behind it. Returns the physics time it went up.
func _duck_behind_wall(enemy: PlayerController) -> float:
	_player.global_position = Vector3(0, 0.1, -20)
	assert_bool(await _until_engaged(enemy)).override_failure_message("never fired on the player").is_true()
	_box(Vector3(0, 1.5, -18), Vector3(10, 3, 0.4))
	await get_tree().physics_frame
	return _now()


func test_a_gunner_keeps_firing_at_the_wall_they_ducked_behind_then_stops() -> void:
	var gunner := await _soldier(Vector3.ZERO, true)
	var ducked := await _duck_behind_wall(gunner)
	await _wait(_seconds() + 2.0)
	var later := _after(ducked + 0.3)
	var into_wall := later.filter(func(s: Dictionary) -> bool:
		var to: Vector3 = s["to"]
		return absf(to.z + 18.0) < 0.5 and absf(to.x) < 5.0)
	assert_int(into_wall.size()).override_failure_message("%d rounds into the wall" % into_wall.size()).is_greater_equal(10)
	if later.is_empty():
		return
	var last := float(later[-1]["at"]) - ducked
	assert_float(last).override_failure_message("last round %.2f s after ducking" % last).is_between(_seconds() - 1.0, _seconds() + 0.5)
	assert_bool(_brain(gunner).target == _player).is_true()


func test_a_rifleman_in_the_same_spot_stops_when_they_duck() -> void:
	var rifleman := await _soldier(Vector3.ZERO, false)
	var ducked := await _duck_behind_wall(rifleman)
	await _wait(_seconds() + 1.0)
	assert_int(_after(ducked + 0.3).size()).is_equal(0)


func test_suppressing_rounds_land_within_the_spread() -> void:
	var gunner := await _soldier(Vector3.ZERO, true)
	var ducked := await _duck_behind_wall(gunner)
	await _wait(_seconds() + 0.5)
	var brain := _brain(gunner)
	var aim_at := brain.last_seen + Vector3.UP * EnemyBrain.CHEST
	var spread := _spread_degrees()
	var widest := 0.0
	var within := 0
	var rounds := _after(ducked + 0.3)
	for s in rounds:
		var from: Vector3 = s["from"]
		var to: Vector3 = s["to"]
		var off := rad_to_deg((to - from).angle_to(aim_at - from))
		widest = maxf(widest, off)
		# The gun's own spread from the shoulder comes on top of the aim point's.
		if off <= spread + 1.5:
			within += 1
	assert_int(rounds.size()).is_greater_equal(10)
	assert_float(float(within) / rounds.size()).override_failure_message("%d of %d within the spread, widest %.1f deg" % [within, rounds.size(), widest]).is_greater_equal(0.9)
	assert_float(widest).is_less(spread + 4.0)
	# Wide on purpose: not every round at one point.
	assert_float(widest).is_greater(spread * 0.4)


## Smoke hides the player but stops no rounds: they stayed in the open, and the stream at
## where they were still finds them.
class FakeSmoke extends Node:
	var thick := false

	func sight_blocked(_from: Vector3, _to: Vector3) -> bool:
		return thick


func test_a_player_who_stays_in_the_open_can_be_hit() -> void:
	var smoke: FakeSmoke = auto_free(FakeSmoke.new())
	smoke.add_to_group(&"sight_blockers")
	add_child(smoke)
	var gunner := await _soldier(Vector3.ZERO, true)
	_player.global_position = Vector3(0, 0.1, -20)
	assert_bool(await _until_engaged(gunner)).is_true()
	var health := _player.get_node("Health") as HealthComponent
	health.invulnerable = false
	health.max_health = 100000.0
	health.server_reset()
	smoke.thick = true
	var hidden := _now()
	await _wait(_seconds())
	var hits := _after(hidden + 0.3).filter(func(s: Dictionary) -> bool: return s.get("target") == _player)
	assert_int(hits.size()).is_greater(0)
	assert_float(health.health).is_less(health.max_health)


func test_a_gunner_does_not_fire_into_a_wall_at_its_muzzle() -> void:
	var smoke: FakeSmoke = auto_free(FakeSmoke.new())
	smoke.thick = true
	smoke.add_to_group(&"sight_blockers")
	add_child(smoke)
	_player.global_position = Vector3(0, 0.1, -20)
	var gunner := await _soldier(Vector3.ZERO, true)
	var brain := _brain(gunner)
	var wall := _box(Vector3(0, 2, -0.9), Vector3(4, 4, 0.2))
	await _loaded(gunner)
	# It was fighting them a moment ago, behind the smoke now.
	var engage := func() -> void:
		brain.target = _player
		brain.last_seen = _player.global_position
		brain.state = EnemyBrain.State.CHASE
		brain.set(&"_engaged_with", _player)
		brain.set(&"_lost_for", 0.0)
	engage.call()
	var aim_at := _player.global_position + Vector3.UP * EnemyBrain.CHEST
	await get_tree().physics_frame
	assert_bool(brain.muzzle_clear(aim_at)).is_false()
	var before := _now()
	await _wait(1.5)
	assert_int(_after(before).size()).is_equal(0)
	# Without the wall the same gunner opens up.
	wall.global_position = Vector3(30, 2, -0.9)
	await get_tree().physics_frame
	assert_bool(brain.muzzle_clear(aim_at)).is_true()
	engage.call()
	before = _now()
	await _wait(1.5)
	assert_int(_after(before).size()).is_greater(0)


func test_while_a_gunner_suppresses_mates_move_without_taking_turns() -> void:
	_player.global_position = Vector3(60, 0.1, 60)
	var mover := await _soldier(Vector3(0, 0, 0), false)
	var waiter := await _soldier(Vector3(3, 0, 0), false)
	var gunner := await _soldier(Vector3(-3, 0, 0), true)
	mover.set_meta(&"moving_to_cover", true)
	assert_bool(bool(_brain(waiter).call(&"_mate_moving"))).is_true()
	gunner.set_meta(&"suppressing", true)
	assert_bool(bool(_brain(waiter).call(&"_mate_moving"))).is_false()
	# A dead gunner covers nobody.
	gunner.set_meta(&"dead", true)
	assert_bool(bool(_brain(waiter).call(&"_mate_moving"))).is_true()


func test_the_gunner_tells_its_mates_while_it_suppresses() -> void:
	var gunner := await _soldier(Vector3.ZERO, true)
	var ducked := await _duck_behind_wall(gunner)
	await _wait(1.0)
	assert_bool(gunner.get_meta(&"suppressing", false)).is_true()
	await _wait(_seconds() + 0.5 - (_now() - ducked))
	assert_bool(gunner.get_meta(&"suppressing", false)).is_false()


func test_when_the_foe_shows_again_the_gunner_fights_as_usual() -> void:
	var gunner := await _soldier(Vector3.ZERO, true)
	await _duck_behind_wall(gunner)
	await _wait(1.0)
	var brain := _brain(gunner)
	assert_bool(gunner.get_meta(&"suppressing", false)).is_true()
	# They step out from behind the wall's end, in sight again.
	_player.global_position = Vector3(8, 0.1, -20)
	await _wait(0.5)
	assert_int(brain.state).is_equal(EnemyBrain.State.FIGHT)
	assert_bool(gunner.get_meta(&"suppressing", false)).is_false()


func test_a_gunner_does_not_suppress_a_foe_who_is_dead() -> void:
	var gunner := await _soldier(Vector3.ZERO, true)
	var ducked := await _duck_behind_wall(gunner)
	_player.set_meta(&"dead", true)
	await _wait(1.5)
	_player.remove_meta(&"dead")
	assert_int(_after(ducked + 0.3).size()).is_equal(0)


func test_a_gunner_does_not_suppress_a_foe_it_only_heard() -> void:
	_player.global_position = Vector3(0, 0.1, -20)
	_box(Vector3(0, 1.5, -18), Vector3(10, 3, 0.4))
	var gunner := await _soldier(Vector3.ZERO, true)
	await _loaded(gunner)
	# Shooting from behind the wall: heard, never seen.
	EventBus.publish(&"weapon.fired", {"holder": _player, "from": _player.global_position + Vector3.UP * 1.5, "to": Vector3(0, 1.5, -30)})
	var heard := _now()
	await _wait(2.0)
	assert_object(_brain(gunner).target).is_same(_player)
	assert_int(_after(heard).size()).is_equal(0)
