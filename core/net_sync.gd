class_name NetSync
extends RefCounted
## Builds MultiplayerSynchronizer nodes for scene builders. The server is the authority for
## everything synchronized; clients only receive. No autoloads used, so builders can call it.


## `always`: properties sent every tick (positions, rotations). `on_change`: properties sent
## only when they change (health, state flags). Paths are relative to the scene root, e.g.
## ".:position" or "Head:rotation".
static func make(always: Array[String], on_change: Array[String] = []) -> MultiplayerSynchronizer:
	var config := SceneReplicationConfig.new()
	for path in always:
		config.add_property(NodePath(path))
		config.property_set_spawn(NodePath(path), true)
		config.property_set_replication_mode(NodePath(path), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	for path in on_change:
		config.add_property(NodePath(path))
		config.property_set_spawn(NodePath(path), true)
		config.property_set_replication_mode(NodePath(path), SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "NetSync"
	# Once a physics tick, when the values change. Left at 0 it sends every frame, and a
	# headless server runs far more frames than ticks, so a moving soldier cost more than
	# twice the bytes for no new information.
	sync.replication_interval = 1.0 / float(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60))
	sync.root_path = NodePath("..")
	sync.replication_config = config
	return sync
