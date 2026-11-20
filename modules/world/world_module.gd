extends Node
## Loads the world, waits until the ground around the spawn has collision, then announces
## it. `--world=flat` loads the flat test world instead (a plain plane: no terrain, scenery
## or road; the test range uses it). Also owns terrain-side reactions: shots that hit the ground dig a small crater, and
## explosions a big one. The ground follows players, enemies and vehicles on its own.

const SCENE := "res://modules/world/scenes/world.tscn"
const FLAT_SCENE := "res://modules/world/scenes/flat_world.tscn"
const CONFIG := "res://modules/world/data/world.json"
## Give up waiting for the spawn area after this long rather than hang a headless server.
const READY_TIMEOUT_SECONDS := 30.0
const BULLET_CRATER_RADIUS := 0.35
const SPAWN_AREA_RADIUS := 16.0
## Metres the map's boundary walls reach past its lowest and highest ground, so nothing
## slips under or over them.
const WALL_MARGIN := 100.0
const MAP_REQUIRED := {"recipe": TYPE_STRING, "seed": TYPE_FLOAT, "kill_depth": TYPE_FLOAT, "car_ahead": TYPE_FLOAT, "car_side": TYPE_FLOAT}

var _voxels: VoxelWorld
var _scenery: SceneryScatter
var _announcement: Dictionary = {}
var _data: Dictionary = {}
## Which world this instance plays: strip, flat (the test range) or map (#472).
var _kind := &"strip"
var _waited := 0.0


## The generated map is played with `--world=map` (#472): its recipe and seed from
## `world.json` `map`, overridden by `--map=` and `--seed=`. True when a map is selected;
## anything else plays the strip.
static func _select_map(args: PackedStringArray, data: Dictionary) -> bool:
	WorldMaps.clear()
	if not args.has("--world=map"):
		return false
	if not (data.get("map") is Dictionary and Data.require(CONFIG + " map", data["map"], MAP_REQUIRED)):
		return false
	var cfg: Dictionary = data["map"]
	var recipe := str(cfg["recipe"])
	var seed_value := int(cfg["seed"])
	for arg in args:
		if arg.begins_with("--map="):
			recipe = arg.trim_prefix("--map=")
		elif arg.begins_with("--seed=") and arg.trim_prefix("--seed=").is_valid_int():
			seed_value = int(arg.trim_prefix("--seed="))
	# A recipe name only, never a path.
	if not recipe.is_valid_filename() or recipe.contains("."):
		Log.warn(&"world", "--map=%s is not a recipe name; playing %s" % [recipe, cfg["recipe"]])
		recipe = str(cfg["recipe"])
	WorldMaps.select(recipe, seed_value)
	# A recipe that is missing or broken: the strip, whole (with its tunnel), not half a map.
	if WorldMaps.shape() == null:
		Log.warn(&"world", "no playable map %s; playing the strip" % recipe)
		WorldMaps.clear()
		return false
	Log.info(&"world", "playing map %s, seed %d" % [recipe, seed_value])
	return true


## Puts the spawn at the map's camp and the car beside it facing down the highway, and fits
## the boundary walls to the map; returns which way the highway leaves the camp.
static func _place_on_map(world: Node, map: MapShape, spawn: Marker3D, car: Marker3D, cfg: Dictionary) -> Vector3:
	var camp := map.camp()
	var forward := map.forward()
	spawn.global_position = camp + Vector3.UP
	var side := forward.cross(Vector3.UP).normalized()
	var at := camp + forward * float(cfg["car_ahead"]) + side * float(cfg["car_side"])
	at.y = map.height_at(at.x, at.z) + 1.0
	# Cars drive along their +Z: the nose points down the highway.
	car.global_transform = Transform3D(Basis.looking_at(-forward, Vector3.UP), at)
	var boundary := world.get_node_or_null("Boundary")
	if boundary != null:
		var area := map.extent()
		var mid_y := (map.low() + map.high()) / 2.0
		var height := map.high() - map.low() + WALL_MARGIN * 2.0
		var walls := {"North": [Vector3(area.get_center().x, mid_y, area.position.y + 1.0), Vector3(area.size.x, height, 2.0)],
			"South": [Vector3(area.get_center().x, mid_y, area.end.y - 1.0), Vector3(area.size.x, height, 2.0)],
			"West": [Vector3(area.position.x + 1.0, mid_y, area.get_center().y), Vector3(2.0, height, area.size.y)],
			"East": [Vector3(area.end.x - 1.0, mid_y, area.get_center().y), Vector3(2.0, height, area.size.y)]}
		for name: String in walls:
			var shape := boundary.get_node_or_null(name) as CollisionShape3D
			if shape == null:
				continue
			var box := BoxShape3D.new()
			box.size = walls[name][1]
			shape.shape = box
			shape.position = walls[name][0]
	return forward


## Performance custom monitors this module publishes, and the method each one reads.
const MONITORS := {&"world/scenery_chunks": &"_monitor_chunks", &"world/trees_felled": &"_monitor_felled"}


func _monitor_chunks() -> int:
	return _scenery.loaded_chunks().size() if is_instance_valid(_scenery) else 0


func _monitor_felled() -> int:
	return _scenery.felled().size() if is_instance_valid(_scenery) else 0


func _ready() -> void:
	var data: Variant = Data.load_json(CONFIG)
	if not data is Dictionary or not Data.require(CONFIG, data, {"kill_y": TYPE_FLOAT, "rescue_depth": TYPE_FLOAT}):
		return
	_data = data
	EventBus.subscribe(&"weapon.fired", _on_weapon_fired)
	EventBus.subscribe(&"explosion", _on_explosion)
	EventBus.subscribe(&"world.tree_felled", _on_tree_felled)
	Net.peer_joined.connect(_on_peer_joined)
	add_to_group(&"world_state")
	# For the perf log (or anything else reading Performance): what the world is holding.
	for monitor: StringName in MONITORS:
		if not Performance.has_custom_monitor(monitor):
			Performance.add_custom_monitor(monitor, Callable(self, MONITORS[monitor]))
	# A client plays whatever its server plays: the world loads once the server says which
	# (`_receive_map`, the first thing it sends a joining peer). Everyone else picks now.
	if _waits_for_server():
		Log.info(&"world", "waiting for the server to say which world it plays")
		return
	var args := Net.session_args()
	_kind = &"flat" if args.has("--world=flat") else &"strip"
	if _select_map(args, data):
		_kind = &"map"
	_load_world()


## Connected to a server as its client (the solo game included): the server's world decides.
func _waits_for_server() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and not peer is OfflineMultiplayerPeer and not multiplayer.is_server()


## Builds the chosen world (`_kind`, and the map WorldMaps has selected) and gets its
## announcement ready.
func _load_world() -> void:
	var data := _data
	var scene: PackedScene = load(FLAT_SCENE if _kind == &"flat" else SCENE)
	var world := scene.instantiate()
	add_child(world)
	# The map viewer on a dedicated server's admin pages (the web module serves them).
	if Net.mode == Net.Mode.SERVER:
		var api := MapApi.new()
		api.name = "MapApi"
		add_child(api)
	_voxels = world.get_node_or_null("Terrain") as VoxelWorld
	_scenery = world.get_node_or_null("Scenery") as SceneryScatter
	if _voxels != null and _scenery != null:
		_voxels.dug.connect(_scenery.on_dug)
	var spawn: Marker3D = world.get_node("SpawnPoint")
	var car: Marker3D = world.get_node("CarSpawn")
	# `front` and `forward`: on the strip players start inside the tunnel, so things spread
	# "around the spawn" (crates, enemies) go around the road just outside it.
	var forward := Vector3.FORWARD
	var kill_y := float(data["kill_y"])
	var map := WorldMaps.shape() if WorldMaps.is_selected() else null
	if map != null:
		forward = _place_on_map(world, map, spawn, car, data["map"])
		kill_y = map.low() - float((data["map"] as Dictionary)["kill_depth"])
	_announcement = {
		"spawn": spawn.global_position,
		"car": car.global_transform,
		"front": Vector3(car.global_position.x, spawn.global_position.y, car.global_position.z),
		"forward": forward,
		"kill_y": kill_y,
		"rescue_depth": data["rescue_depth"],
	}


## Server to a joining client, before anything else about the world: which world it plays
## (`kind` strip, flat or map) and, for a map, its recipe and seed. The client builds the same.
@rpc("authority", "call_remote", "reliable")
func _receive_map(kind: String, recipe: String, seed_value: int) -> void:
	if _voxels != null or not _waits_for_server():
		return
	WorldMaps.clear()
	_kind = &"strip"
	if kind == "flat":
		_kind = &"flat"
	elif kind == "map":
		WorldMaps.select(recipe, seed_value)
		if WorldMaps.shape() == null:
			Net.leave("This server plays the map %s, which this game does not have." % recipe)
			return
		_kind = &"map"
	Log.info(&"world", "the server plays %s" % ("map %s, seed %d" % [recipe, seed_value] if _kind == &"map" else String(_kind)))
	_load_world()


func _exit_tree() -> void:
	for monitor: StringName in MONITORS:
		if Performance.has_custom_monitor(monitor):
			Performance.remove_custom_monitor(monitor)
	EventBus.unsubscribe(&"weapon.fired", _on_weapon_fired)
	EventBus.unsubscribe(&"explosion", _on_explosion)
	EventBus.unsubscribe(&"world.tree_felled", _on_tree_felled)
	if Net.peer_joined.is_connected(_on_peer_joined):
		Net.peer_joined.disconnect(_on_peer_joined)


func _on_explosion(p: Dictionary) -> void:
	if _voxels == null:
		return
	_voxels.server_dig(p["position"], float(p["radius"]))
	if _is_server() and _scenery != null:
		var blasted := _scenery.server_blast_trees(p["position"], float(p["radius"]))
		for id: Vector2i in blasted:
			var hit: Dictionary = blasted[id]
			_broadcast_fell(id, hit["direction"], hit["cut"], hit["blast"])


func _is_server() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()


func _broadcast_fell(id: Vector2i, direction: Vector3, cut: float, blast: Vector4 = Vector4.ZERO) -> void:
	Net.server_broadcast(&"world.tree_felled", {"chunk": id.x, "index": id.y, "direction": direction, "cut": cut, "blast": blast})


func _on_tree_felled(p: Dictionary) -> void:
	if _scenery == null:
		return
	_scenery.fell_tree(Vector2i(int(p["chunk"]), int(p["index"])), p["direction"], float(p.get("cut", 1.0)), p.get("blast", Vector4.ZERO))


## Someone joining late gets every tree already down, lying where it fell, as dry as it is.
func _on_peer_joined(peer: int) -> void:
	if not _is_server():
		return
	# Which world first: the client builds it before the craters and trees below arrive.
	_receive_map.rpc_id(peer, String(_kind), WorldMaps.recipe_name(), WorldMaps.seed_value())
	# Craters first, so trees and loot settle on the ground as it is now.
	if _voxels != null and not _voxels.dig_log().is_empty():
		_receive_digs.rpc_id(peer, _digs_as_list())
	if _scenery == null:
		return
	var list := _felled_as_list()
	if not list.is_empty():
		_receive_felled.rpc_id(peer, list)


@rpc("authority", "call_remote", "reliable")
func _receive_digs(list: Array) -> void:
	for d: Array in list:
		_voxels.replay_dig(Vector4(float(d[0]), float(d[1]), float(d[2]), float(d[3])))


func _digs_as_list() -> Array:
	var out: Array = []
	for d in _voxels.dig_log():
		out.append([d.x, d.y, d.z, d.w])
	return out


func _felled_as_list() -> Array:
	var list: Array = []
	if _scenery == null:
		return list
	var felled := _scenery.felled()
	for id: Vector2i in felled:
		var info: Dictionary = felled[id]
		list.append([id.x, id.y, info["direction"], info["cut"], info["blast"], _scenery.felled_age(id)])
	return list


## The `world_state` contract (persistence): craters and felled trees, kept across restarts.
func world_state_owner() -> String:
	return "world"


## 2: trees by square chunk ids (#472); a version-1 save's tree ids point elsewhere.
func world_state_version() -> int:
	return 2


func server_world_state() -> Dictionary:
	return {"digs": _digs_as_list() if _voxels != null else [], "felled": _felled_as_list()}


func server_restore_world_state(version: int, data: Variant) -> void:
	if version != 2 or not data is Dictionary:
		Log.warn(&"world", "saved world damage is version %d; this game reads 2, so it starts undamaged" % version)
		return
	var d: Dictionary = data
	if _voxels != null:
		_receive_digs(d.get("digs", []))
	if _scenery != null:
		_receive_felled(d.get("felled", []))


@rpc("authority", "call_remote", "reliable")
func _receive_felled(list: Array) -> void:
	for entry: Array in list:
		# At least a moment old, so it lies still instead of falling again.
		var seconds_ago := maxf(float(entry[5]) if entry.size() > 5 else 0.0, 0.01)
		_scenery.fell_tree(Vector2i(int(entry[0]), int(entry[1])), entry[2], float(entry[3]), entry[4], seconds_ago)


func _process(delta: float) -> void:
	var prof := Prof.start()
	_process_tick(delta)
	Prof.stop(&"world/module:frame", prof)


func _process_tick(delta: float) -> void:
	if _announcement.is_empty():
		return
	_waited += delta
	var spawn: Vector3 = _announcement["spawn"]
	# Meshes can be ready a frame or two before their collision, and things spawn up to ~8 m
	# from the spawn point (the car), so wait for a wider area and a real physics hit.
	var ready := (_voxels == null or _voxels.is_ready_at(spawn, SPAWN_AREA_RADIUS)) and _ground_hit(spawn)
	if ready or _waited > READY_TIMEOUT_SECONDS:
		if _waited > READY_TIMEOUT_SECONDS:
			Log.warn(&"world", "spawn terrain not ready after %.0f s, announcing anyway" % READY_TIMEOUT_SECONDS)
		var payload := _announcement
		_announcement = {}
		EventBus.publish(&"world.ready", payload)


func _ground_hit(at: Vector3) -> bool:
	var space := get_viewport().find_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 20.0, at + Vector3.DOWN * 40.0, PhysicsLayers.SOLID)
	return not space.intersect_ray(query).is_empty()


func _on_weapon_fired(p: Dictionary) -> void:
	var hit: Variant = p.get("collider")
	if hit is Node and (hit as Node).has_meta(&"chunk"):
		_scenery.bite_tree(hit, p["to"], p["from"])
		if _is_server():
			var felled: Variant = _scenery.server_shoot_tree(hit, p["to"])
			if felled is Dictionary:
				_broadcast_fell(felled["id"], (p["to"] as Vector3) - (p["from"] as Vector3), felled["cut"])
	if hit is Node and (hit as Node).is_in_group(&"terrain") and float(p.get("damage", 0.0)) == 0.0:
		_voxels.server_dig(p["to"], BULLET_CRATER_RADIUS)
