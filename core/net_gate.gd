class_name NetGate
extends Node
## Replication reaches only peers the server has let in (#552): a peer that is refused or
## kicked hangs up on its own, and until the server notices, ENet has already dropped its
## channels, so anything sent to it logged "Unable to send packet on channel 0". Every
## MultiplayerSynchronizer on this session's multiplayer is filtered by
## `NetSession.replicates_to` (hello accepted, not being kicked).
##
## Godot decides a spawn's visibility only from synchronizers on it, so spawn functions are
## wrapped to give a spawned node without one an empty synchronizer. Spawn packets list the
## spawn's synchronizers, so the wrapper runs on the server and every client alike. Spawners
## must set `spawn_function` before they enter the tree. A new module gets all this by using
## a MultiplayerSpawner and MultiplayerSynchronizer as usual.

const GATE_NAME := "NetGate"

## Whose `replicates_to` decides (the Net autoload, or a session a test runs).
var session: NetSession
## The filtered synchronizers (as keys), to show to or hide from one peer when it joins or is
## kicked.
var _syncs: Dictionary[MultiplayerSynchronizer, bool] = {}


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)


## Every filtered synchronizer looks at `peer` again: after it joined, or as it is kicked.
## Spawns it may now see are sent at once; those it may not are taken back.
func update_for(peer: int) -> void:
	for sync: MultiplayerSynchronizer in _syncs:
		if is_instance_valid(sync) and sync.is_inside_tree():
			sync.update_visibility(peer)


func synchronizer_count() -> int:
	return _syncs.size()


func _on_node_added(node: Node) -> void:
	var t := Prof.start()
	var sync := node as MultiplayerSynchronizer
	if sync != null:
		_gate_sync(sync)
	else:
		var spawner := node as MultiplayerSpawner
		if spawner != null:
			_gate_spawner(spawner)
	Prof.stop(&"net/gate", t)


func _gate_sync(sync: MultiplayerSynchronizer) -> void:
	# Tests run their own server and client side by side under other multiplayer branches.
	if sync.multiplayer != multiplayer or _syncs.has(sync):
		return
	sync.add_visibility_filter(session.replicates_to)
	# Visibility changes only on join and kick (and NetRelevance's own calls): asking the
	# filter every frame for every synchronizer would cost for nothing.
	sync.visibility_update_mode = MultiplayerSynchronizer.VISIBILITY_PROCESS_NONE
	_syncs[sync] = true
	sync.tree_exiting.connect(_forget.bind(sync), CONNECT_ONE_SHOT)
	# It registered with replication on entering the tree, before the filter: shown to
	# everyone connected until this.
	sync.update_visibility(0)


func _forget(sync: MultiplayerSynchronizer) -> void:
	_syncs.erase(sync)


func _gate_spawner(spawner: MultiplayerSpawner) -> void:
	if spawner.multiplayer != multiplayer or spawner.has_meta(&"net_gate"):
		return
	var make := spawner.spawn_function
	if not make.is_valid():
		Log.warn(&"net", "spawner %s has no spawn_function when it enters the tree; what it spawns reaches peers before they join" % spawner.get_path())
		return
	spawner.set_meta(&"net_gate", true)
	spawner.spawn_function = spawn_gated.bind(spawner, make)


## `make`'s node, with an empty synchronizer when it has none of its own, so the gate's filter
## decides who it is spawned for. Offline (tests) nothing is replicated, so nothing is added.
static func spawn_gated(data: Variant, spawner: MultiplayerSpawner, make: Callable) -> Node:
	var node: Node = make.call(data)
	var peer := spawner.multiplayer.multiplayer_peer
	if node == null or peer == null or peer is OfflineMultiplayerPeer or has_synchronizer(node):
		return node
	node.add_child(gate_synchronizer())
	return node


static func has_synchronizer(node: Node) -> bool:
	for child in node.get_children():
		if child is MultiplayerSynchronizer:
			return true
	return false


## Replicates nothing; only carries the visibility of the node it sits on.
static func gate_synchronizer() -> MultiplayerSynchronizer:
	var sync := MultiplayerSynchronizer.new()
	sync.name = GATE_NAME
	sync.root_path = NodePath("..")
	sync.replication_config = SceneReplicationConfig.new()
	# It has nothing to send; left at 0, replication would visit it for every peer every frame.
	sync.replication_interval = 3600.0
	sync.delta_interval = 3600.0
	return sync
