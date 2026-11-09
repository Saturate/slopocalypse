extends Node
## Enemy soldiers: squads that appear around the map, patrol, and fight players. Each one
## is the real player body and guns driven by an EnemyBrain on the server, spawned through
## a MultiplayerSpawner so everyone sees them. They carry random loot (the inventory module
## fills their backpack) and drop it when they die; squads come back over time so the map
## never empties.

## Ground probes start this far over the untouched ground, or over the point itself.
const PROBE_ABOVE_GROUND := 3.0
const PROBE_ABOVE_SELF := 1.5
const SCENE := "res://modules/player/scenes/player.tscn"
const CONFIG := "res://modules/enemies/data/enemies.json"
const REQUIRED := {
	"first_spawn_seconds": TYPE_FLOAT, "max_alive": TYPE_FLOAT, "squad_size": TYPE_ARRAY,
	"squad_respawn_seconds": TYPE_FLOAT, "spawn_distance": TYPE_ARRAY, "corpse_seconds": TYPE_FLOAT,
	"max_health": TYPE_FLOAT, "patrol_radius": TYPE_FLOAT, "patrol_pause_seconds": TYPE_ARRAY,
	"walk_speed_share": TYPE_FLOAT, "sight_range": TYPE_FLOAT, "sight_cone_degrees": TYPE_FLOAT,
	"hearing_range": TYPE_FLOAT, "reaction_seconds": TYPE_FLOAT, "aim_error_degrees": TYPE_ARRAY,
	"aim_settle_seconds": TYPE_FLOAT, "turn_speed": TYPE_FLOAT, "burst_shots": TYPE_ARRAY,
	"burst_pause_seconds": TYPE_ARRAY, "chase_seconds": TYPE_FLOAT, "forget_seconds": TYPE_FLOAT,
	"damage_scale": TYPE_FLOAT, "uniform_tint": TYPE_ARRAY,
}
## Enemy peer ids count down from here so they never collide with real peers.
const FIRST_ID := -1000

var config: Dictionary = {}
var _spawner := MultiplayerSpawner.new()
var _spawned := 0
var _spawn := Vector3.ZERO
var _world_ready := false
## The open side of the spawn (zero when every direction is open).
var _forward := Vector3.ZERO
var _next_squad_in := -1.0
var _rng := RandomNumberGenerator.new()

## Kept loaded: Godot's resource cache lets go of a scene once nothing holds it, and loading
## a generated scene again from text costs tens of milliseconds per spawn.
var _packed_scene: PackedScene


func _scene() -> PackedScene:
	if _packed_scene == null:
		_packed_scene = load(SCENE)
	return _packed_scene


func _ready() -> void:
	_spawner.name = "Spawner"
	_spawner.spawn_path = NodePath("..")
	_spawner.spawn_function = _make_enemy
	add_child(_spawner)
	var data: Variant = Data.load_json(CONFIG)
	if not data is Dictionary or not Data.require(CONFIG, data, REQUIRED):
		return
	config = data
	_rng.randomize()
	EventBus.subscribe(&"world.ready", _on_world_ready)
	EventBus.subscribe(&"enemy.died", _on_enemy_died)
	EventBus.subscribe(&"admin.spawn", _on_admin_spawn)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"world.ready", _on_world_ready)
	EventBus.unsubscribe(&"enemy.died", _on_enemy_died)
	EventBus.unsubscribe(&"admin.spawn", _on_admin_spawn)


func enemies() -> Array[Node]:
	return get_tree().get_nodes_in_group(&"enemies").filter(func(n: Node) -> bool: return not n.get_meta(&"dead", false))


func _on_world_ready(payload: Dictionary) -> void:
	# Squads come from the open side: around the road outside the start tunnel, ahead of it.
	_spawn = payload.get("front", payload.get("spawn", Vector3.ZERO))
	_forward = payload.get("forward", Vector3.ZERO)
	_world_ready = true
	if multiplayer.is_server():
		_next_squad_in = float(config["first_spawn_seconds"])


func _physics_process(delta: float) -> void:
	var prof := Prof.start()
	_physics_tick(delta)
	Prof.stop(&"enemies/module:physics", prof)


func _physics_tick(delta: float) -> void:
	if not multiplayer.is_server() or not _world_ready or _next_squad_in < 0.0:
		return
	_next_squad_in -= delta
	if _next_squad_in > 0.0:
		return
	_next_squad_in = float(config["squad_respawn_seconds"])
	var room := int(config["max_alive"]) - enemies().size()
	if room > 0:
		server_spawn_squad(mini(room, _roll(config["squad_size"])))


## Server: a squad of `size` around a random point in the ring around the spawn.
func server_spawn_squad(size: int, centre: Variant = null) -> Array[Node]:
	var at: Vector3
	if centre is Vector3:
		at = centre
	else:
		var ring: Array = config["spawn_distance"]
		var a := _rng.randf() * TAU
		if _forward != Vector3.ZERO:
			a = atan2(_forward.z, _forward.x) + _rng.randf_range(-PI / 2.0, PI / 2.0)
		at = _spawn + Vector3(cos(a), 0.0, sin(a)) * _rng.randf_range(float(ring[0]), float(ring[1]))
	var out: Array[Node] = []
	for i in size:
		var offset := Vector3(_rng.randf_range(-3.0, 3.0), 0.0, _rng.randf_range(-3.0, 3.0))
		var pos := _on_ground(at + offset) + Vector3.UP * 0.5
		_spawned += 1
		out.append(_spawner.spawn({"index": _spawned, "position": pos, "home": at}))
	return out


## Runs on the server and, through the spawner, on every client.
func _make_enemy(data: Variant) -> Node:
	var info: Dictionary = data
	var prof := Prof.start()
	var enemy: PlayerController = _scene().instantiate()
	Prof.stop(&"enemies/instantiate", prof)
	enemy.name = "Enemy%d" % int(info["index"])
	enemy.position = info["position"]
	enemy.set_meta(&"peer_id", FIRST_ID - int(info["index"]))
	enemy.set_meta(&"team", "enemies")
	enemy.add_to_group(&"enemies")
	if not multiplayer.is_server():
		enemy.set_physics_process(false)
	enemy.ready.connect(_on_enemy_ready.bind(enemy, info["home"]), CONNECT_ONE_SHOT)
	return enemy


func _on_enemy_ready(enemy: PlayerController, home: Vector3) -> void:
	var health := enemy.get_node("Health") as HealthComponent
	health.max_health = config["max_health"]
	health.server_reset()
	# Weapons equip it, the inventory fills its pockets with loot, the world streams
	# terrain around it on the server.
	EventBus.publish(&"player.spawned", {"player": enemy, "local": false, "npc": true})
	# Their guns hit softer than a player's, so a squad is a fight rather than a wipe.
	for weapon in enemy.get_node("Head/Camera").get_children():
		if weapon is HitscanWeapon:
			weapon.stats["damage"] = float(weapon.stats.get("damage", 0.0)) * float(config["damage_scale"])
	if multiplayer.is_server():
		health.died.connect(_server_died.bind(enemy))
		var brain := EnemyBrain.new()
		brain.name = "Brain"
		brain.body = enemy
		brain.config = config
		brain.home = home
		enemy.add_child(brain)
	if DisplayServer.get_name() != "headless":
		_tint(enemy)
		var animator := PlayerBodyAnimator.new()
		animator.name = "BodyAnimator"
		animator.player = enemy
		enemy.add_child(animator)


## A different uniform so enemies read as enemies at a glance: the same body, tinted.
func _tint(enemy: Node) -> void:
	var c: Array = config["uniform_tint"]
	var tint := Color(float(c[0]), float(c[1]), float(c[2]))
	for path in ["Body/Skeleton/Mesh", "Body/Skeleton/Arms"]:
		var mesh := enemy.get_node_or_null(path) as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		var mat := mesh.mesh.surface_get_material(0)
		if mat is BaseMaterial3D:
			var copy := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
			copy.albedo_color = tint
			mesh.material_override = copy


func _server_died(source: Node, enemy: PlayerController) -> void:
	if enemy.get_meta(&"dead", false):
		return
	Net.server_broadcast(&"enemy.died", {"enemy": enemy, "source": source, "position": enemy.global_position})
	# Connected to the body itself, so the timer quietly forgets it if it is gone first.
	get_tree().create_timer(float(config["corpse_seconds"])).timeout.connect(enemy.queue_free)


## Everywhere: the soldier drops (hidden, not hittable) and its gun goes quiet.
func _on_enemy_died(p: Dictionary) -> void:
	var enemy := p.get("enemy") as PlayerController
	if enemy == null:
		return
	enemy.set_meta(&"dead", true)
	(enemy.get_node("Body") as Node3D).visible = false
	(enemy.get_node("Shape") as CollisionShape3D).set_deferred(&"disabled", true)
	if multiplayer.is_server():
		enemy.set_physics_process(false)


func _roll(range_pair: Array) -> int:
	return _rng.randi_range(int(range_pair[0]), int(range_pair[1]))


func _on_ground(at: Vector3) -> Vector3:
	var world := get_viewport().find_world_3d()
	if world == null:
		return at
	# From just over the ground (or over `at` when that is higher, e.g. on a roof), not from
	# high above: under a roof, like in the start tunnel, that would land on the roof.
	var from_y := at.y + 30.0
	var ground_node := get_tree().get_first_node_in_group(&"ground")
	if ground_node != null and ground_node.has_method(&"ground_height"):
		from_y = maxf(at.y + PROBE_ABOVE_SELF, float(ground_node.call(&"ground_height", at.x, at.z)) + PROBE_ABOVE_GROUND)
	var query := PhysicsRayQueryParameters3D.create(Vector3(at.x, from_y, at.z), at + Vector3.DOWN * 60.0, PhysicsLayers.SOLID)
	var hit := world.direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		return hit["position"]
	# Far from players the server has no terrain loaded; the height map knows anyway.
	var ground := get_tree().get_first_node_in_group(&"ground")
	if ground != null and ground.has_method(&"ground_height"):
		return Vector3(at.x, float(ground.call(&"ground_height", at.x, at.z)), at.z)
	return at


## Server: an admin asked for a squad in front of them.
func _on_admin_spawn(p: Dictionary) -> void:
	if p.get("kind") == "squad" and multiplayer.is_server():
		server_spawn_squad(int(p.get("count", 3)), p["position"])
