class_name NetRelevance
extends Node
## Server: each client is sent only the far-flung things near its own player. A node whose
## root carries the meta `net_relevance` (soldiers, drones: many of them, spread over the map)
## has its synchronizer shown to a peer only while it is within `relevance_distance` of that
## peer's player, and hidden again past `relevance_distance + relevance_margin`, so it doesn't
## flicker at the edge. A node spawned by a MultiplayerSpawner is spawned on a peer when it
## becomes visible to it, with its current state, and despawned when it stops being visible.
## Players and cars are few and always visible; anything else keeps Godot's default. A player
## in a car counts where the car is (`PlayerSpot`).
##
## Checked every `relevance_seconds` (data/net.json), and at once for a new node, so nothing
## far away is ever spawned on a client first.

const CONFIG := "res://data/net.json"
const REQUIRED := {"relevance_distance": TYPE_FLOAT, "relevance_margin": TYPE_FLOAT, "relevance_seconds": TYPE_FLOAT}

var reach := 300.0
var margin := 40.0
var every := 0.25
var _tracked: Array[MultiplayerSynchronizer] = []
var _since := 0.0


func _ready() -> void:
	var data: Variant = Data.load_json(CONFIG)
	if data is Dictionary and Data.require(CONFIG, data, REQUIRED):
		reach = float(data["relevance_distance"])
		margin = float(data["relevance_margin"])
		every = float(data["relevance_seconds"])
	get_tree().node_added.connect(_on_node_added)
	multiplayer.peer_connected.connect(func(_id: int) -> void: _update())


## Whether something `distance` away stays or becomes relevant: inside `reach`, or, if it
## already was, inside `reach + margin`.
static func relevant(was: bool, distance: float, reach_m: float, margin_m: float) -> bool:
	return distance <= reach_m + (margin_m if was else 0.0)


func tracked_count() -> int:
	return _tracked.size()


func _on_node_added(node: Node) -> void:
	var sync := node as MultiplayerSynchronizer
	if sync == null or sync.multiplayer != multiplayer or not multiplayer.is_server():
		return
	var root := sync.get_node_or_null(sync.root_path)
	if root == null or not root.has_meta(&"net_relevance") or not root is Node3D:
		return
	sync.public_visibility = false
	_tracked.append(sync)
	sync.tree_exiting.connect(func() -> void: _tracked.erase(sync), CONNECT_ONE_SHOT)
	_apply(sync, _player_spots())


func _process(delta: float) -> void:
	_since += delta
	if _since < every:
		return
	_since = 0.0
	var t := Prof.start()
	_update()
	Prof.stop(&"net/relevance", t)


func _update() -> void:
	if not multiplayer.is_server():
		return
	var spots := _player_spots()
	for sync in _tracked:
		if is_instance_valid(sync):
			_apply(sync, spots)


## Peer -> where its player is, or the car they sit in.
func _player_spots() -> Dictionary[int, Vector3]:
	var out: Dictionary[int, Vector3] = {}
	var cars := PlayerSpot.cars_api(get_tree())
	for p: Node in get_tree().get_nodes_in_group(&"players"):
		var id := int(p.get_meta(&"peer_id", 0))
		if id > 0 and p is Node3D and p.multiplayer == multiplayer:
			out[id] = PlayerSpot.of(p as Node3D, cars)
	return out


func _apply(sync: MultiplayerSynchronizer, spots: Dictionary[int, Vector3]) -> void:
	var root := sync.get_node_or_null(sync.root_path) as Node3D
	if root == null or not root.is_inside_tree():
		return
	var at := root.global_position
	for peer in multiplayer.get_peers():
		var was := sync.get_visibility_for(peer)
		var now := spots.has(peer) and relevant(was, at.distance_to(spots[peer]), reach, margin)
		if now != was:
			sync.set_visibility_for(peer, now)
