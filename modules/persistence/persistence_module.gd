extends Node
## Server only: keeps progress between sessions in an SQLite file (`SaveStore`, in Rust).
## Per player, by name: backpack, changed gun builds, health and position. For the world:
## loot lying on the ground and what each crate holds. A player is loaded when they spawn
## and saved when they leave; the world is loaded once it is ready; everything is saved
## every `autosave_seconds`, when the last player leaves and when the server stops on its
## own. A killed server loses at most `autosave_seconds`.
##
## A name belongs to the key that first used it (`PlayerProfile` on the client); anyone
## else joining under it is sent back to the menu with the reason.
## Talks to the inventory and weapons through their API groups, and works without them.
## `--save=PATH` picks the file, `--no-save` turns saving off for tool runs.

## A saved spot this far under the ground is inside it: the world changed since the save.
const BURIED_DEPTH := 1.0
const CONFIG := "res://modules/persistence/data/persistence.json"
const FIELDS := {"file": TYPE_STRING, "autosave_seconds": TYPE_FLOAT, "hold_seconds": TYPE_FLOAT}
## A save that lives only as long as the server (tests).
const MEMORY := ":memory:"

## Only a real server saves; scenes run without Boot (tests) switch it on by hand.
var enabled := Net.mode == NetSession.Mode.SERVER
var store: SaveStore
var config: Dictionary = {}

## Peer -> the name their progress is saved under.
var _names: Dictionary = {}
var _until_save := 0.0
## Player put back where they logged out -> seconds left to wait for ground under them.
var _holding: Dictionary = {}


func _ready() -> void:
	if enabled:
		start("")


## Starts saving to `path`, or to the configured file (or `--save=`) when "". Tests pass
## MEMORY.
func start(path: String) -> bool:
	enabled = false
	var data: Variant = Data.load_json(CONFIG)
	if not data is Dictionary or not Data.require(CONFIG, data, FIELDS):
		return false
	config = data
	if path.is_empty():
		path = save_path(OS.get_cmdline_user_args(), str(config["file"]))
		if path.is_empty():
			Log.info(&"persistence", "saving is off (--no-save)")
			return false
	if not open(path):
		return false
	enabled = true
	_until_save = float(config["autosave_seconds"])
	EventBus.subscribe(&"player.spawned", _on_player_spawned)
	EventBus.subscribe(&"world.ready", _on_world_ready)
	Net.peer_leaving.connect(_on_peer_leaving)
	Net.stopping.connect(server_save_all)
	return true


func _exit_tree() -> void:
	EventBus.unsubscribe(&"player.spawned", _on_player_spawned)
	EventBus.unsubscribe(&"world.ready", _on_world_ready)
	if Net.peer_leaving.is_connected(_on_peer_leaving):
		Net.peer_leaving.disconnect(_on_peer_leaving)
		Net.stopping.disconnect(server_save_all)


## A server window closed by hand saves on the way out.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and enabled:
		server_save_all()


## `--no-save` gives "", `--save=PATH` gives PATH, otherwise the configured file.
static func save_path(args: PackedStringArray, configured: String) -> String:
	var path := configured
	for arg in args:
		if arg == "--no-save":
			return ""
		if arg.begins_with("--save="):
			path = arg.trim_prefix("--save=")
	return path


## Opens the save file (`user://` or an OS path, or MEMORY).
func open(path: String) -> bool:
	store = SaveStore.new()
	var os_path := ProjectSettings.globalize_path(path) if path != MEMORY else ""
	if not os_path.is_empty():
		DirAccess.make_dir_recursive_absolute(os_path.get_base_dir())
	if not store.open(os_path):
		Log.error(&"persistence", "could not open the save %s: %s" % [os_path, store.last_error()])
		return false
	Log.info(&"persistence", "saving to %s" % (os_path if not os_path.is_empty() else "memory"))
	return true


func _physics_process(delta: float) -> void:
	if not enabled:
		return
	_hold_until_grounded(delta)
	_until_save -= delta
	if _until_save <= 0.0:
		_until_save = float(config.get("autosave_seconds", 60.0))
		server_save_all()


## The world module announces once the spawn has ground; the inventory lays out crates and
## loot on the same event, so the saved world is put back after every handler has run.
func _on_world_ready(_p: Dictionary) -> void:
	server_load_world.call_deferred()


func server_load_world() -> void:
	var inventory := _inventory()
	if inventory == null:
		return
	var world := store.load_world()
	if world.is_empty():
		Log.info(&"persistence", "no saved world yet; starting fresh")
		return
	inventory.call(&"server_restore_world", world)
	Log.info(&"persistence", "world loaded: %d loot on the ground, %d crates" % [(world["loot"] as Array).size(), (world["crates"] as Array).size()])


func _on_player_spawned(p: Dictionary) -> void:
	if p.get("npc", false):
		return
	var peer := int((p["player"] as Node).get_meta(&"peer_id", 0))
	var who := Net.identity_of(peer)
	if who.is_empty():
		return
	# After the inventory and weapons have given the newcomer their defaults.
	server_admit.call_deferred(peer, str(who["name"]), str(who["key"]))


## Server: ties `peer` to a saved name and gives back what was saved under it. Sends them
## away if the name is not allowed, already playing, or someone else's. Returns whether
## they are in.
func server_admit(peer: int, raw_name: String, key: String) -> bool:
	var player_name := store.clean_name(raw_name)
	if player_name.is_empty():
		Net.server_kick(peer, "The name \"%s\" can't be used: %s." % [raw_name, store.last_error()])
		return false
	for other: String in _names.values():
		if other.nocasecmp_to(player_name) == 0:
			Net.server_kick(peer, "%s is already playing on this server." % player_name)
			return false
	match store.claim(player_name, key):
		"wrong_key":
			Net.server_kick(peer, "The name %s is taken on this server. Pick another name in the menu." % player_name)
			return false
		"returning":
			_names[peer] = player_name
			_restore(peer, store.load_player(player_name))
			Log.info(&"persistence", "%s is back" % player_name)
		"new":
			_names[peer] = player_name
			server_save_player(peer)
			Log.info(&"persistence", "%s is new here" % player_name)
		_:
			Log.error(&"persistence", "could not look up %s: %s; they play unsaved" % [player_name, store.last_error()])
			return false
	return true


func name_of(peer: int) -> String:
	return str(_names.get(peer, ""))


func _restore(peer: int, saved: Dictionary) -> void:
	if saved.is_empty():
		return
	var inventory := _inventory()
	if inventory != null:
		inventory.call(&"server_restore_items", peer, saved.get("items", []))
	var weapons := get_tree().get_first_node_in_group(&"weapons_api")
	if weapons != null:
		weapons.call(&"server_restore_builds", peer, saved.get("builds", {}))
	var player := _player_of(peer)
	var at: Variant = saved.get("position")
	# Saved dead (or never placed): they start over at the spawn like a respawn would.
	if player == null or not at is Vector3 or float(saved.get("health", 0.0)) <= 0.0:
		return
	# The world may have changed under the spot since (a mountain where the road was):
	# a spot now inside the ground starts them at the spawn instead, gear and all.
	if _buried(at as Vector3):
		Log.info(&"persistence", "%s's saved spot is under the ground now; starting at the spawn" % name_of(peer))
		return
	(player.get_node("Health") as HealthComponent).server_set(float(saved["health"]))
	player.global_position = (at as Vector3) + Vector3.UP * 0.2
	player.velocity = Vector3.ZERO
	# Terrain only streams in around players, so it may not be there yet: hang in place
	# until it is instead of falling through.
	player.set_physics_process(false)
	_holding[player] = float(config.get("hold_seconds", 10.0))


## Under the untouched ground by more than BURIED_DEPTH, asking the world's height function.
func _buried(at: Vector3) -> bool:
	var ground := get_tree().get_first_node_in_group(&"ground")
	if ground == null or not ground.has_method(&"ground_height"):
		return false
	return at.y < float(ground.call(&"ground_height", at.x, at.z)) - BURIED_DEPTH


func _hold_until_grounded(delta: float) -> void:
	for player: CharacterBody3D in _holding.keys():
		if not is_instance_valid(player):
			_holding.erase(player)
			continue
		_holding[player] = float(_holding[player]) - delta
		if _has_ground(player) or float(_holding[player]) <= 0.0:
			_holding.erase(player)
			if not player.get_meta(&"dead", false):
				player.set_physics_process(true)


func _has_ground(player: CharacterBody3D) -> bool:
	var at := player.global_position
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP, at + Vector3.DOWN * 40.0, PhysicsLayers.SOLID)
	query.exclude = [player.get_rid()]
	return not player.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Server: writes `peer`'s progress. Dead players are saved without a position: their
## backpack is already on the ground (saved with the world) and they start at the spawn.
func server_save_player(peer: int) -> bool:
	var player_name := name_of(peer)
	if player_name.is_empty():
		return false
	var player := _player_of(peer)
	var health := player.get_node_or_null("Health") as HealthComponent if player != null else null
	var dead := player == null or health == null or bool(player.get_meta(&"dead", false)) or health.is_dead()
	var inventory := _inventory()
	var weapons := get_tree().get_first_node_in_group(&"weapons_api")
	var save := {
		"health": 0.0 if dead else health.health,
		"position": null if dead else player.global_position,
		"items": inventory.call(&"server_items_of", peer) if inventory != null else [],
		"builds": weapons.call(&"server_builds_of", peer) if weapons != null else {},
	}
	if not store.save_player(player_name, save):
		Log.error(&"persistence", "could not save %s: %s" % [player_name, store.last_error()])
		return false
	return true


func server_save_world() -> bool:
	var inventory := _inventory()
	if inventory == null:
		return false
	if not store.save_world(inventory.call(&"server_world_state")):
		Log.error(&"persistence", "could not save the world: %s" % store.last_error())
		return false
	return true


func server_save_all() -> void:
	for peer: int in _names.keys():
		server_save_player(peer)
	server_save_world()


## The player is gone from the network but still in the world: save them now. The last one
## out also saves the world, since a solo or hosted server quits right after.
func _on_peer_leaving(peer: int) -> void:
	server_save_player(peer)
	_names.erase(peer)
	if _names.is_empty():
		server_save_world()


func _inventory() -> Node:
	return get_tree().get_first_node_in_group(&"inventory_api")


func _player_of(peer: int) -> CharacterBody3D:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		if int(node.get_meta(&"peer_id", 0)) == peer:
			return node as CharacterBody3D
	return null
