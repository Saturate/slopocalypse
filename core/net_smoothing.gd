class_name NetSmoothing
extends Node
## Client: things whose root carries the meta `net_smooth` (other players, soldiers, drones;
## set by the module that spawns them) are shown `delay` seconds in the past, blended between
## the server updates either side (NetSmoothTrack), instead of jumping to each one as it
## arrives. Only properties sent every tick are smoothed; the rest apply when they arrive.
##
## Your own player never opts in: its camera would lag by the delay.

const CONFIG := "res://data/net.json"
const REQUIRED := {"smooth_delay": TYPE_FLOAT, "smooth_extrapolate": TYPE_FLOAT, "smooth_snap_distance": TYPE_FLOAT}

var delay := 0.05
var extrapolate := 0.1
var snap_distance := 5.0

## Synchronizer -> {root, targets: Array of [node, property path, kind], track}.
var _entries: Dictionary[MultiplayerSynchronizer, Dictionary] = {}


func _ready() -> void:
	var data: Variant = Data.load_json(CONFIG)
	if data is Dictionary and Data.require(CONFIG, data, REQUIRED):
		delay = float(data["smooth_delay"])
		extrapolate = float(data["smooth_extrapolate"])
		snap_distance = float(data["smooth_snap_distance"])
	get_tree().node_added.connect(_on_node_added)


func tracked_count() -> int:
	return _entries.size()


static func _now() -> float:
	return float(Time.get_ticks_usec()) / 1000000.0


func _on_node_added(node: Node) -> void:
	var sync := node as MultiplayerSynchronizer
	if sync == null or sync.multiplayer != multiplayer or multiplayer.is_server():
		return
	# The synchronizer is added after its root got the meta, but before the root is ready.
	var root := sync.get_parent()
	if root == null or not root.get_meta(&"net_smooth", false):
		return
	sync.ready.connect(_track.bind(sync), CONNECT_ONE_SHOT)


func _track(sync: MultiplayerSynchronizer) -> void:
	var root := sync.get_node_or_null(sync.root_path)
	var config := sync.replication_config
	if root == null or config == null:
		return
	var targets: Array = []
	var track := NetSmoothTrack.new()
	for path in config.get_properties():
		if config.property_get_replication_mode(path) != SceneReplicationConfig.REPLICATION_MODE_ALWAYS:
			continue
		var node := root.get_node_or_null(NodePath(path.get_concatenated_names()))
		var property := NodePath(path.get_concatenated_subnames())
		if node == null:
			continue
		var value: Variant = node.get_indexed(property)
		if not (value is float or value is Vector3):
			continue
		if node == root and String(property) == "position":
			track.snap_index = targets.size()
		track.kinds.append(NetSmoothTrack.ANGLE if String(property).begins_with("rotation") else NetSmoothTrack.LINEAR)
		targets.append([node, property])
	if targets.is_empty():
		return
	var entry := {"targets": targets, "track": track}
	_entries[sync] = entry
	_record(sync)
	sync.synchronized.connect(_record.bind(sync))
	sync.tree_exiting.connect(func() -> void: _entries.erase(sync), CONNECT_ONE_SHOT)


## The synchronizer has just written the server's values: keep them, then show the smoothed ones
## again in `_process`.
func _record(sync: MultiplayerSynchronizer) -> void:
	var entry: Dictionary = _entries.get(sync, {})
	if entry.is_empty():
		return
	var values: Array = []
	for target: Array in entry["targets"]:
		values.append((target[0] as Node).get_indexed(target[1]))
	(entry["track"] as NetSmoothTrack).push(_now(), values)


func _process(_delta: float) -> void:
	if _entries.is_empty():
		return
	var t := Prof.start()
	var now := _now()
	for entry: Dictionary in _entries.values():
		var track: NetSmoothTrack = entry["track"]
		track.delay = delay
		track.extrapolate = extrapolate
		track.snap_distance = snap_distance
		var values := track.sample(now)
		var targets: Array = entry["targets"]
		for i in values.size():
			(targets[i][0] as Node).set_indexed(targets[i][1], values[i])
	Prof.stop(&"net/smoothing", t)
