extends Node
## Loads the world (the generated map, decision 0012), waits until the ground around the
## spawn has collision, then announces it. `--world=flat` loads the flat test world instead (a
## plain plane: no terrain, scenery or road; the test range uses it). Also owns terrain-side
## reactions: shots that hit the ground dig a small crater, and explosions a big one. The
## ground follows players, enemies and vehicles on its own.
##
## The map builds on a worker thread (#515): the scene loads once it is done, and what arrives
## for the world meanwhile (craters, felled trees) waits in `_held` until then.

const SCENE := "res://modules/world/scenes/world.tscn"
const FLAT_SCENE := "res://modules/world/scenes/flat_world.tscn"
const CONFIG := "res://modules/world/data/world.json"
## Give up waiting for the spawn area after this long rather than hang a headless server.
const READY_TIMEOUT_SECONDS := 30.0
const BULLET_CRATER_RADIUS := 0.35
const SPAWN_AREA_RADIUS := 16.0
const MAP_REQUIRED := {"recipe": TYPE_STRING, "seed": TYPE_FLOAT, "kill_depth": TYPE_FLOAT}

var _voxels: VoxelWorld
var _scenery: SceneryScatter
var _announcement: Dictionary = {}
var _data: Dictionary = {}
## Which world this instance plays: map (#472) or flat (the test range); empty when the
## map could not be built.
var _kind := &""
var _waited := 0.0
## While the map builds on a worker thread; the world scene loads when it is done.
var _building := false
## Whether this player's screen says the world is loading (`session.loading`), until it is
## announced.
var _loading_shown := false
var _build_started := 0
## Whether the world scene is in; until then world events wait in `_held`.
var _loaded := false
## World events that came before the world was loaded, applied in order once it is.
var _held: Array[Callable] = []


## The generated map is the world (#472, decision 0012): its recipe and seed from
## `world.json` `map`, overridden by `--map=` and `--seed=`. A recipe that is missing or
## broken falls back to world.json's; true when a playable map is selected.
static func _select_map(args: PackedStringArray, cfg: Dictionary) -> bool:
	WorldMaps.clear()
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
	if not WorldMaps.is_playable(recipe) and recipe != str(cfg["recipe"]):
		Log.warn(&"world", "no playable map %s; playing %s" % [recipe, cfg["recipe"]])
		recipe = str(cfg["recipe"])
	WorldMaps.select(recipe, seed_value)
	if not WorldMaps.is_playable(recipe):
		Log.error(&"world", "no playable map %s (%s); no world loaded" % [recipe, WorldMaps.MAPS_DIR])
		WorldMaps.clear()
		return false
	Log.info(&"world", "playing map %s, seed %d" % [recipe, seed_value])
	return true


## Performance custom monitors this module publishes, and the method each one reads.
const MONITORS := {&"world/scenery_chunks": &"_monitor_chunks", &"world/trees_felled": &"_monitor_felled"}


func _monitor_chunks() -> int:
	return _scenery.loaded_chunks().size() if is_instance_valid(_scenery) else 0


func _monitor_felled() -> int:
	return _scenery.felled().size() if is_instance_valid(_scenery) else 0


func _ready() -> void:
	var data: Variant = Data.load_json(CONFIG)
	if not data is Dictionary or not Data.require(CONFIG, data, {"rescue_depth": TYPE_FLOAT, "map": TYPE_DICTIONARY}):
		return
	if not Data.require(CONFIG + " map", data["map"], MAP_REQUIRED):
		return
	_data = data
	EventBus.subscribe(&"weapon.fired", _on_weapon_fired)
	EventBus.subscribe(&"explosion", _on_explosion)
	EventBus.subscribe(&"world.tree_felled", _on_tree_felled)
	Net.peer_joined.connect(_on_peer_joined)
	add_to_group(&"world_state")
	add_to_group(&"world_map")
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
	WorldMaps.clear()
	if args.has("--world=flat"):
		_kind = &"flat"
	elif _select_map(args, data["map"]):
		_kind = &"map"
	else:
		return
	_build_world()


## Whether the world is loaded and announced here, and its ground built (meshes and
## collision) within `radius` of `point`. Tools (playtest screenshots) wait on this.
func is_ready_at(point: Vector3, radius: float) -> bool:
	if not _loaded or _building or not _announcement.is_empty() or _loading_shown:
		return false
	return _voxels == null or _voxels.is_ready_at(point, radius)


## Which world this instance plays, as a save keys it (#472): "flat", or the map's recipe, a
## hash of the recipe file (an edited recipe moves things) and its seed.
func map_key() -> String:
	if _kind != &"map":
		return String(_kind)
	var text := FileAccess.get_file_as_string(WorldMaps.MAPS_DIR.path_join(WorldMaps.recipe_name() + ".json"))
	return "map:%s:%s:%d" % [WorldMaps.recipe_name(), text.sha256_text().left(12), WorldMaps.seed_value()]


## Connected to a server as its client (the solo game included): the server's world decides.
func _waits_for_server() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and not peer is OfflineMultiplayerPeer and not multiplayer.is_server()


## Starts the chosen world: the flat one loads at once, a map once its build on a worker
## thread is done (`_poll_build`).
func _build_world() -> void:
	if _kind != &"map":
		_load_world()
		return
	if not WorldMaps.start_build():
		Log.error(&"world", "no playable map %s; no world loaded" % WorldMaps.recipe_name())
		_no_world()
		return
	_building = true
	_build_started = Time.get_ticks_msec()
	_show_loading(true)


## Each frame while the map builds: loads the world once it is done.
func _poll_build() -> void:
	if WorldMaps.is_building():
		return
	_building = false
	if WorldMaps.shape() == null:
		Log.error(&"world", "the map %s did not build; no world loaded" % WorldMaps.recipe_name())
		_no_world()
		return
	Log.info(&"world", "map built in %d ms on a worker thread" % (Time.get_ticks_msec() - _build_started))
	var prof := Prof.start()
	_load_world()
	Prof.stop(&"world/load", prof)


## No world after all: nothing waits for one, and a save is left alone (an empty `map_key`).
func _no_world() -> void:
	_kind = &""
	_held.clear()
	_show_loading(false)


## The card stays up through loading the scene (a long frame) until the world is announced.
func _show_loading(on: bool) -> void:
	if on == _loading_shown or not Net.has_local_player():
		return
	_loading_shown = on
	EventBus.publish(&"session.loading", {"text": "Loading the world..." if on else ""})


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
	# The world scene put these on the map's camp (WorldRoot); the flat world's stand still.
	var spawn: Marker3D = world.get_node("SpawnPoint")
	var car: Marker3D = world.get_node("CarSpawn")
	var forward := Vector3.FORWARD
	# The flat world's ground is at 0.
	var low := 0.0
	var map := WorldMaps.shape() if _kind == &"map" else null
	if map != null:
		forward = map.forward()
		low = map.low()
	var kill_y := low - float((data["map"] as Dictionary)["kill_depth"])
	_announcement = {
		"spawn": spawn.global_position,
		"car": car.global_transform,
		"front": Vector3(car.global_position.x, spawn.global_position.y, car.global_position.z),
		"forward": forward,
		"kill_y": kill_y,
		"rescue_depth": data["rescue_depth"],
	}
	# The players' camp (CampLayout): the map's, or on the flat world one round its spawn.
	var camp: Variant = world.get("camp")
	_announcement["camp"] = camp if camp is CampLayout else CampLayout.of_ready(_announcement)
	_loaded = true
	var held := _held
	_held = []
	for apply in held:
		apply.call()


## Until the world is loaded, `apply` waits its turn; true when it was held. A server whose
## map could not be built never loads one, so nothing waits there.
func _hold(apply: Callable) -> bool:
	if _loaded or (_kind == &"" and not _waits_for_server()):
		return false
	_held.append(apply)
	return true


## Server to a joining client, before anything else about the world: which world it plays
## (`kind` flat or map) and, for a map, its recipe and seed. The client builds the same.
@rpc("authority", "call_remote", "reliable")
func _receive_map(kind: String, recipe: String, seed_value: int) -> void:
	if _kind != &"" or not _waits_for_server():
		return
	WorldMaps.clear()
	if kind == "flat":
		_kind = &"flat"
	else:
		# A recipe name only, never a path.
		if kind != "map" or not recipe.is_valid_filename() or recipe.contains(".") or not WorldMaps.is_playable(recipe):
			Net.leave("This server plays the map %s, which this game does not have." % recipe)
			return
		WorldMaps.select(recipe, seed_value)
		_kind = &"map"
	# The digs and felled trees sent right after this cover every crater and tree that came
	# before it; replaying those too would dig them twice.
	_held.clear()
	Log.info(&"world", "the server plays %s" % ("map %s, seed %d" % [recipe, seed_value] if _kind == &"map" else String(_kind)))
	_build_world()


func _exit_tree() -> void:
	_show_loading(false)
	# The selection is static: the next session (or test) picks its own world. Waits for a
	# build still running.
	WorldMaps.clear()
	for monitor: StringName in MONITORS:
		if Performance.has_custom_monitor(monitor):
			Performance.remove_custom_monitor(monitor)
	EventBus.unsubscribe(&"weapon.fired", _on_weapon_fired)
	EventBus.unsubscribe(&"explosion", _on_explosion)
	EventBus.unsubscribe(&"world.tree_felled", _on_tree_felled)
	if Net.peer_joined.is_connected(_on_peer_joined):
		Net.peer_joined.disconnect(_on_peer_joined)


func _on_explosion(p: Dictionary) -> void:
	if _hold(_on_explosion.bind(p)) or _voxels == null:
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
	if _hold(_on_tree_felled.bind(p)) or _scenery == null:
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
	if _hold(_receive_digs.bind(list)) or _voxels == null:
		return
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


## 3: trees by square chunk ids with the spawn clearing round the camp (#472); older saves'
## tree ids point at other trees.
func world_state_version() -> int:
	return 3


func server_world_state() -> Dictionary:
	return {"digs": _digs_as_list() if _voxels != null else [], "felled": _felled_as_list()}


func server_restore_world_state(version: int, data: Variant) -> void:
	if version != 3 or not data is Dictionary:
		Log.warn(&"world", "saved world damage is version %d; this game reads 3, so it starts undamaged" % version)
		return
	var d: Dictionary = data
	if _voxels != null:
		_receive_digs(d.get("digs", []))
	if _scenery != null:
		_receive_felled(d.get("felled", []))
	# Someone who joined while this server's map was still building was sent no damage then.
	if not _is_server() or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return
	for peer in multiplayer.get_peers():
		if Net.identity_of(peer).is_empty():
			continue
		if not (d.get("digs", []) as Array).is_empty():
			_receive_digs.rpc_id(peer, d["digs"])
		if not (d.get("felled", []) as Array).is_empty():
			_receive_felled.rpc_id(peer, d["felled"])


@rpc("authority", "call_remote", "reliable")
func _receive_felled(list: Array) -> void:
	if _hold(_receive_felled.bind(list)) or _scenery == null:
		return
	for entry: Array in list:
		# At least a moment old, so it lies still instead of falling again.
		var seconds_ago := maxf(float(entry[5]) if entry.size() > 5 else 0.0, 0.01)
		_scenery.fell_tree(Vector2i(int(entry[0]), int(entry[1])), entry[2], float(entry[3]), entry[4], seconds_ago)


func _process(delta: float) -> void:
	var prof := Prof.start()
	_process_tick(delta)
	Prof.stop(&"world/module:frame", prof)


func _process_tick(delta: float) -> void:
	if _building:
		# Loading the world is a long frame of its own; the spawn check waits for the next.
		_poll_build()
		return
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
		_show_loading(false)
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
