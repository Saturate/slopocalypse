extends GdUnitTestSuite
## The rocket launcher: a gun whose receiver fires projectiles. A rocket flies, arms after a
## few metres and blows up on what it meets through the shared explosion; one that hits too
## close is a dud; the backblast hurts whoever stands behind the tube.

const PLAYER := "res://modules/player/scenes/player.tscn"
const WEAPONS := "res://modules/weapons/weapons_module.gd"
const RIFLE := "res://modules/weapons/scenes/rifle.tscn"

var _weapons: Node
var _ground: StaticBody3D
var _blasts: Array[Dictionary] = []


func before_test() -> void:
	_ground = auto_free(_box(Vector3(0, -0.5, 0), Vector3(200, 1, 200)))
	_weapons = auto_free((load(WEAPONS) as GDScript).new())
	add_child(_weapons)
	_blasts.clear()
	EventBus.subscribe(&"explosion", _on_blast)


func after_test() -> void:
	EventBus.unsubscribe(&"explosion", _on_blast)


func _on_blast(p: Dictionary) -> void:
	_blasts.append(p)


func _box(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	body.global_position = at
	return body


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func test_a_rocket_flies_and_blows_up_on_a_wall() -> void:
	auto_free(_box(Vector3(0, 1.5, -20), Vector3(6, 4, 0.4)))
	_weapons.call(&"spawn_rocket", Vector3(0, 1.5, 0), Vector3(0, 0, -55), null)
	await _frames(60)
	assert_int(_blasts.size()).is_equal(1)
	assert_float((_blasts[0]["position"] as Vector3).z).is_between(-20.0, -18.0)


func test_a_rocket_that_hits_too_close_is_a_dud() -> void:
	auto_free(_box(Vector3(0, 1.5, -2), Vector3(6, 4, 0.4)))
	_weapons.call(&"spawn_rocket", Vector3(0, 1.5, 0), Vector3(0, 0, -55), null)
	await _frames(30)
	assert_array(_blasts).is_empty()
	assert_int(_weapons.get_children().filter(func(n: Node) -> bool: return n is Rocket).size()).is_equal(0)


func test_the_launcher_launches_and_its_backblast_hurts_behind() -> void:
	var shooter: PlayerController = auto_free((load(PLAYER) as PackedScene).instantiate())
	shooter.set_meta(&"peer_id", 1)
	shooter.add_to_group(&"players")
	add_child(shooter)
	shooter.global_position = Vector3.ZERO
	var behind: PlayerController = auto_free((load(PLAYER) as PackedScene).instantiate())
	behind.set_meta(&"peer_id", 2)
	behind.add_to_group(&"players")
	add_child(behind)
	behind.global_position = Vector3(0, 0, 2.0)
	behind.set_physics_process(false)
	var launcher: HitscanWeapon = (load(RIFLE) as PackedScene).instantiate()
	launcher.set_script(RocketLauncher)
	launcher.holder = shooter
	launcher.stats = GunAssembly.assemble_named("launcher")["stats"]
	launcher.set(&"rockets_parent", _weapons)
	shooter.get_node("Head/Camera").add_child(launcher)
	await _frames(2)
	var health := behind.get_node("Health") as HealthComponent
	launcher.server_fire(Vector3(0, 1.6, 0), Vector3(0, 0, -1))
	await get_tree().physics_frame
	assert_int(_weapons.get_children().filter(func(n: Node) -> bool: return n is Rocket).size()).is_equal(1)
	assert_float(health.health).is_less(health.max_health)
	# One rocket a load: the next pull does nothing until it reloads.
	launcher.server_fire(Vector3(0, 1.6, 0), Vector3(0, 0, -1))
	await get_tree().physics_frame
	assert_int(_weapons.get_children().filter(func(n: Node) -> bool: return n is Rocket).size()).is_equal(1)
