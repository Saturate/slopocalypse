extends Node
## Enemy soldiers: squads that appear around the map, patrol, and fight players. Each one
## is the real player body and guns driven by an EnemyBrain on the server, spawned through
## a MultiplayerSpawner so everyone sees them. They carry random loot (the inventory module
## fills their backpack) and drop it when they die; squads come back over time so the map
## never empties. Other modules (missions) place guards through the `enemies_api` group:
## `server_spawn_guard` puts one on a post, or on a patrol route.

## Ground probes start this far over the untouched ground, or over the point itself.
const PROBE_ABOVE_GROUND := 3.0
const PROBE_ABOVE_SELF := 1.5
const SCENE := "res://modules/player/scenes/player.tscn"
const CONFIG := "res://modules/enemies/data/enemies.json"
const REQUIRED := {
	"first_spawn_seconds": TYPE_FLOAT, "max_alive": TYPE_FLOAT, "squad_size": TYPE_ARRAY,
	"squad_respawn_seconds": TYPE_FLOAT, "spawn_area": TYPE_ARRAY, "spawn_clear": TYPE_FLOAT, "corpse_seconds": TYPE_FLOAT,
	"max_health": TYPE_FLOAT, "patrol_radius": TYPE_FLOAT, "patrol_pause_seconds": TYPE_ARRAY,
	"walk_speed_share": TYPE_FLOAT, "sight_range": TYPE_FLOAT, "sight_cone_degrees": TYPE_FLOAT,
	"hearing_range": TYPE_FLOAT, "reaction_seconds": TYPE_FLOAT, "aim_error_degrees": TYPE_ARRAY,
	"aim_settle_seconds": TYPE_FLOAT, "turn_speed": TYPE_FLOAT, "burst_shots": TYPE_ARRAY,
	"burst_pause_seconds": TYPE_ARRAY, "chase_seconds": TYPE_FLOAT, "forget_seconds": TYPE_FLOAT,
	"damage_scale": TYPE_FLOAT, "uniform_tint": TYPE_ARRAY,
}
## Enemy peer ids count down from here so they never collide with real peers.
const FIRST_ID := -1000
## Tries at a squad spot clear of every player before taking the last one.
const SPOT_TRIES := 8

var config: Dictionary = {}
var _spawner := MultiplayerSpawner.new()
var _spawned := 0
var _spawn := Vector3.ZERO
var _world_ready := false
## The open side of the spawn (zero when every direction is open).
var _forward := Vector3.ZERO
var _next_squad_in := -1.0
var _rng := RandomNumberGenerator.new()
## Server: filling up to `max_alive` a soldier a tick, once `first_spawn_seconds` have passed.
var _filling := false
## Server: soldiers of the map's own squads still to land, one a tick: each costs a few
## milliseconds to set up, and a whole squad in one tick stalled the server.
var _queued: Array[Dictionary] = []
var _filled_once := false

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
	add_to_group(&"enemies_api")
	_rng.randomize()
	EventBus.subscribe(&"world.ready", _on_world_ready)
	EventBus.subscribe(&"enemy.died", _on_enemy_died)
	EventBus.subscribe(&"civilian.died", _on_civilian_died)
	EventBus.subscribe(&"enemy.surrendered", _on_enemy_surrendered)
	EventBus.subscribe(&"admin.spawn", _on_admin_spawn)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"world.ready", _on_world_ready)
	EventBus.unsubscribe(&"enemy.died", _on_enemy_died)
	EventBus.unsubscribe(&"civilian.died", _on_civilian_died)
	EventBus.unsubscribe(&"enemy.surrendered", _on_enemy_surrendered)
	EventBus.unsubscribe(&"admin.spawn", _on_admin_spawn)


func enemies() -> Array[Node]:
	return get_tree().get_nodes_in_group(&"enemies").filter(func(n: Node) -> bool: return not n.get_meta(&"dead", false))


func _on_world_ready(payload: Dictionary) -> void:
	# Squads live on the open side of the start: around and ahead of the road out of the
	# start tunnel, spread over `spawn_area`.
	_spawn = payload.get("front", payload.get("spawn", Vector3.ZERO))
	_forward = payload.get("forward", Vector3.ZERO)
	_world_ready = true
	if multiplayer.is_server():
		_next_squad_in = float(config["first_spawn_seconds"])
		if Net.session_args().has(DeathsBot.FLAG) and get_node_or_null("DeathsBot") == null:
			var bot := DeathsBot.new()
			bot.name = "DeathsBot"
			bot.enemies = self
			add_child(bot)
		var crowd := crowd_arg(OS.get_cmdline_user_args())
		if crowd > 0:
			config = config.duplicate()
			config["max_alive"] = float(crowd)


## `--crowd=N` from the command line (benchmarks: exactly N alive), or 0.
static func crowd_arg(args: PackedStringArray) -> int:
	for arg in args:
		if arg.begins_with("--crowd="):
			return maxi(0, int(arg.trim_prefix("--crowd=")))
	return 0


func _physics_process(delta: float) -> void:
	var prof := Prof.start()
	_physics_tick(delta)
	Prof.stop(&"enemies/module:physics", prof)


func _physics_tick(delta: float) -> void:
	if not multiplayer.is_server() or not _world_ready or _next_squad_in < 0.0:
		return
	if not _queued.is_empty():
		_spawn_one(_queued.pop_front())
		return
	if _filling:
		# The first fill: squads until `max_alive`, their soldiers landing one a tick.
		var room := int(config["max_alive"]) - enemies().size()
		if room <= 0:
			_filling = false
		else:
			# Lands from the next tick on, as the respawn's do.
			_queued = _plan_squad(mini(room, _roll(config["squad_size"])))
		return
	_next_squad_in -= delta
	if _next_squad_in > 0.0:
		return
	_next_squad_in = float(config["squad_respawn_seconds"])
	if not _filled_once:
		_filled_once = true
		_filling = true
		return
	var room := int(config["max_alive"]) - enemies().size()
	if room > 0:
		_queued = _plan_squad(mini(room, _roll(config["squad_size"])))


## A spot for a squad: somewhere in `spawn_area` (metres out from the start, on its open
## side), and at least `spawn_clear` from every player so nobody sees them appear. After a
## few tries it takes the last spot.
func _spread_spot() -> Vector3:
	var area: Array = config["spawn_area"]
	var clear := float(config["spawn_clear"])
	var players := get_tree().get_nodes_in_group(&"players").filter(func(n: Node) -> bool: return int(n.get_meta(&"peer_id", 0)) > 0 and n is Node3D)
	var spot := _spawn
	for attempt in SPOT_TRIES:
		var a := _rng.randf() * TAU
		if _forward != Vector3.ZERO:
			a = atan2(_forward.z, _forward.x) + _rng.randf_range(-PI / 2.0, PI / 2.0)
		# Even over the area, not bunched near its inner edge.
		var r := sqrt(_rng.randf_range(pow(float(area[0]), 2.0), pow(float(area[1]), 2.0)))
		spot = _spawn + Vector3(cos(a), 0.0, sin(a)) * r
		if players.all(func(p: Node) -> bool: return (p as Node3D).global_position.distance_to(spot) >= clear):
			break
	return spot


## Server: a squad of `size` around `centre`, or around a spread spot (`_spread_spot`), all
## at once (admin spawns, missions, tests). The map's own squads land a soldier a tick.
func server_spawn_squad(size: int, centre: Variant = null) -> Array[Node]:
	var out: Array[Node] = []
	for info in _plan_squad(size, centre):
		out.append(_spawn_one(info))
	return out


## Spawn data for a squad of `size` around `centre` or a spread spot: one faction to a squad
## (the factions module picks by weight; without it, one side). Its first soldier may be the
## faction's marksman, with their own gear.
func _plan_squad(size: int, centre: Variant = null) -> Array[Dictionary]:
	var at: Vector3 = centre if centre is Vector3 else _spread_spot()
	var api := _factions()
	var faction := str(api.call(&"pick", _rng)) if api != null else ""
	var marksman := marksman_gear(api.call(&"info", faction) if api != null else {}, _rng.randf())
	var out: Array[Dictionary] = []
	for i in size:
		var offset := Vector3(_rng.randf_range(-3.0, 3.0), 0.0, _rng.randf_range(-3.0, 3.0))
		var info := {"position": _on_ground(at + offset) + Vector3.UP * 0.5, "home": at, "faction": faction}
		if i == 0 and not marksman.is_empty():
			info["gear"] = marksman
		out.append(info)
	return out


## The gear a squad's marksman wears, or empty when this squad has none: a faction with
## `marksman` in its data (`squad_chance`, and `gear` worn instead of the faction's in those
## slots) brings one when `roll` (0 to 1) is under the chance.
static func marksman_gear(faction: Dictionary, roll: float) -> Dictionary:
	var marksman: Dictionary = faction.get("marksman", {})
	if marksman.is_empty() or roll >= float(marksman.get("squad_chance", 0.0)):
		return {}
	var gear: Dictionary = (faction.get("gear", {}) as Dictionary).duplicate()
	gear.merge(marksman.get("gear", {}), true)
	return gear


func _spawn_one(info: Dictionary) -> Node:
	_spawned += 1
	info["index"] = _spawned
	return _spawner.spawn(info)


func _factions() -> Node:
	return get_tree().get_first_node_in_group(&"factions_api") if is_inside_tree() else null


## Server: one guard standing at `at` watching `yaw`, or walking `route` (points) round and
## round if it has any. Like any soldier it fights when it spots or hears someone, then goes
## back to its post or route.
func server_spawn_guard(at: Vector3, yaw: float, route: Array = [], faction := "") -> Node:
	_spawned += 1
	if faction.is_empty():
		var api := _factions()
		faction = str(api.call(&"guard_faction")) if api != null else ""
	# Exactly there: posts are on floors the caller knows, and a probe from above would put a
	# guard meant to stand inside a building on its roof.
	return _spawner.spawn({"index": _spawned, "position": at + Vector3.UP * 0.3, "home": at, "post_yaw": yaw, "route": route, "faction": faction})


## Server: an unarmed civilian at `at` (#342), strolling near there and running to the
## nearest of `refuges` (world positions, building doors) when shooting starts. Same body,
## network sync and relevance as soldiers; their own side, which nobody is hostile to.
func server_spawn_civilian(at: Vector3, yaw: float, refuges: Array) -> Node:
	_spawned += 1
	return _spawner.spawn({"index": _spawned, "position": at + Vector3.UP * 0.3, "home": at, "post_yaw": yaw, "civilian": true, "refuges": refuges})


func civilians() -> Array[Node]:
	return get_tree().get_nodes_in_group(&"civilians").filter(func(n: Node) -> bool: return not n.get_meta(&"dead", false))


## Runs on the server and, through the spawner, on every client.
func _make_enemy(data: Variant) -> Node:
	var info: Dictionary = data
	var prof := Prof.start()
	var enemy: PlayerController = _scene().instantiate()
	Prof.stop(&"enemies/instantiate", prof)
	var civilian: bool = info.get("civilian", false)
	enemy.name = ("Civilian%d" if civilian else "Enemy%d") % int(info["index"])
	enemy.position = info["position"]
	enemy.set_meta(&"peer_id", FIRST_ID - int(info["index"]))
	# A soldier's side is its faction; without factions, all soldiers are one side.
	var faction := str(info.get("faction", ""))
	enemy.set_meta(&"team", "civilians" if civilian else (faction if not faction.is_empty() else "enemies"))
	enemy.set_meta(&"faction", faction)
	enemy.set_meta(&"civilian", civilian)
	# Many, spread over the map: each client is sent only those near it (NetRelevance).
	enemy.set_meta(&"net_relevance", true)
	enemy.set_meta(&"net_smooth", true)
	# Soldiers count and scan the `enemies` group; civilians are neither.
	enemy.add_to_group(&"civilians" if civilian else &"enemies")
	if not multiplayer.is_server():
		PlayerController.hold_still(enemy)
	enemy.rotation.y = float(info.get("post_yaw", 0.0))
	enemy.ready.connect(_on_enemy_ready.bind(enemy, info["home"], info), CONNECT_ONE_SHOT)
	return enemy


func _on_enemy_ready(enemy: PlayerController, home: Vector3, info: Dictionary = {}) -> void:
	var prof := Prof.start()
	_set_up(enemy, home, info)
	Prof.stop(&"enemies/set_up", prof)


## Runs as each soldier or civilian enters the tree, on the server and every client.
func _set_up(enemy: PlayerController, home: Vector3, info: Dictionary = {}) -> void:
	if enemy.get_meta(&"civilian", false):
		_on_civilian_ready(enemy, home, info)
		return
	var health := enemy.get_node("Health") as HealthComponent
	health.max_health = config["max_health"]
	health.server_reset()
	# Weapons equip it, the inventory fills its pockets with loot, the world streams
	# terrain around it on the server.
	# Their guns hit softer than a player's, so a squad is a fight rather than a wipe (the
	# weapons module applies it to whatever gun they hold).
	enemy.set_meta(&"damage_scale", float(config["damage_scale"]))
	var api := _factions()
	var faction: Dictionary = api.call(&"info", str(enemy.get_meta(&"faction", ""))) if api != null else {}
	var spawned := {"player": enemy, "local": false, "npc": true}
	if faction.has("gear"):
		spawned["gear"] = faction["gear"]
	# A squad's marksman wears their own.
	if info.has("gear"):
		spawned["gear"] = info["gear"]
	EventBus.publish(&"player.spawned", spawned)
	if multiplayer.is_server():
		health.died.connect(_server_died.bind(enemy))
		# Server-local: who hurt whom, for faction standing.
		health.damaged.connect(func(_amount: float, source: Node) -> void:
			EventBus.publish(&"enemy.hurt", {"enemy": enemy, "source": source}))
		var brain := EnemyBrain.new()
		brain.name = "Brain"
		brain.body = enemy
		brain.config = _leaning(faction)
		brain.home = home
		if info.has("post_yaw"):
			brain.post_yaw = float(info["post_yaw"])
			brain.has_post = true
		for point: Variant in info.get("route", []):
			brain.route.append(point as Vector3)
		enemy.add_child(brain)
	if DisplayServer.get_name() != "headless":
		_tint(enemy, faction.get("tint", config["uniform_tint"]))
		var animator := PlayerBodyAnimator.new()
		animator.name = "BodyAnimator"
		animator.player = enemy
		enemy.add_child(animator)


func _on_civilian_ready(person: PlayerController, home: Vector3, info: Dictionary) -> void:
	var cfg: Dictionary = config.get("civilians", {})
	var health := person.get_node("Health") as HealthComponent
	health.max_health = float(cfg.get("max_health", 60.0))
	health.server_reset()
	# No gun, no gear: the weapons module equips nothing for an unarmed body.
	EventBus.publish(&"player.spawned", {"player": person, "local": false, "npc": true, "unarmed": true, "gear": {}})
	if multiplayer.is_server():
		health.died.connect(func(source: Node) -> void:
			if person.get_meta(&"dead", false):
				return
			Net.server_broadcast(&"civilian.died", {"civilian": person, "source": source, "position": person.global_position})
			get_tree().create_timer(float(config["corpse_seconds"])).timeout.connect(person.queue_free))
		var brain := CivilianBrain.new()
		brain.name = "Brain"
		brain.body = person
		brain.config = cfg
		brain.home = home
		for r: Variant in info.get("refuges", []):
			brain.refuges.append(r as Vector3)
		person.add_child(brain)
	if DisplayServer.get_name() != "headless":
		var clothes: Array = cfg.get("clothes", [[0.6, 0.6, 0.6]])
		_tint(person, clothes[int(info["index"]) % clothes.size()])
		var animator := PlayerBodyAnimator.new()
		animator.name = "BodyAnimator"
		animator.player = person
		person.add_child(animator)


## Everywhere: a civilian drops like a soldier does.
func _on_civilian_died(p: Dictionary) -> void:
	_on_enemy_died({"enemy": p.get("civilian"), "source": p.get("source")})


## The soldiers' config with a faction's leanings: how far it sees and hears.
func _leaning(faction: Dictionary) -> Dictionary:
	if faction.is_empty():
		return config
	var out := config.duplicate()
	out["sight_range"] = float(config["sight_range"]) * float(faction.get("sight", 1.0))
	out["hearing_range"] = float(config["hearing_range"]) * float(faction.get("hearing", 1.0))
	return out


## A different uniform so enemies read as enemies at a glance (each faction its own): the same
## body, tinted.
func _tint(enemy: Node, c: Array) -> void:
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


## Everywhere: the soldier drops (hidden, not hittable) and its gun goes quiet; on clients a
## ragdoll of it falls in its place.
func _on_enemy_died(p: Dictionary) -> void:
	var enemy := p.get("enemy") as PlayerController
	if enemy == null or enemy.get_meta(&"dead", false):
		return
	Corpse.from_body(enemy, Corpse.push_from(enemy, p.get("source")))
	enemy.set_meta(&"dead", true)
	(enemy.get_node("Body") as Node3D).visible = false
	(enemy.get_node("Shape") as CollisionShape3D).set_deferred(&"disabled", true)
	if multiplayer.is_server():
		enemy.set_physics_process(false)


## Everywhere: a soldier gave up: its gun goes away (out of its hands, and it cannot fire).
func _on_enemy_surrendered(p: Dictionary) -> void:
	var enemy := p.get("enemy") as PlayerController
	if enemy == null:
		return
	enemy.set_meta(&"surrendered", true)
	for weapon in enemy.get_node("Head/Camera").get_children():
		if weapon is HitscanWeapon:
			(weapon as HitscanWeapon).active = false
	var socket := PlayerBody.weapon_socket(enemy)
	var held := socket.get_node_or_null("HeldRifle") as Node3D if socket != null else null
	if held != null:
		held.visible = false


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
