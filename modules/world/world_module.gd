extends Node
## Loads the world, waits until the terrain around the spawn has collision, then announces
## it. Also owns terrain-side reactions: players get a voxel viewer so terrain streams around
## them, and shots that hit the ground dig a small crater.

const SCENE := "res://modules/world/scenes/world.tscn"
const CONFIG := "res://modules/world/data/world.json"
## Give up waiting for the spawn area after this long rather than hang a headless server.
const READY_TIMEOUT_SECONDS := 30.0
const BULLET_CRATER_RADIUS := 0.35

var _voxels: VoxelWorld
var _announcement: Dictionary = {}
var _waited := 0.0


func _ready() -> void:
	var data: Variant = Data.load_json(CONFIG)
	if not data is Dictionary or not Data.require(CONFIG, data, {"kill_y": TYPE_FLOAT}):
		return
	var scene: PackedScene = load(SCENE)
	var world := scene.instantiate()
	add_child(world)
	_voxels = world.get_node("Terrain")
	var spawn: Marker3D = world.get_node("SpawnPoint")
	_announcement = {"spawn": spawn.global_position, "kill_y": data["kill_y"]}
	EventBus.subscribe(&"player.spawned", _on_player_spawned)
	EventBus.subscribe(&"weapon.fired", _on_weapon_fired)
	EventBus.subscribe(&"explosion", _on_explosion)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"player.spawned", _on_player_spawned)
	EventBus.unsubscribe(&"weapon.fired", _on_weapon_fired)
	EventBus.unsubscribe(&"explosion", _on_explosion)


func _on_explosion(p: Dictionary) -> void:
	_voxels.server_dig(p["position"], float(p["radius"]))


func _process(delta: float) -> void:
	if _announcement.is_empty():
		return
	_waited += delta
	var spawn: Vector3 = _announcement["spawn"]
	if _voxels.is_ready_at(spawn) or _waited > READY_TIMEOUT_SECONDS:
		if _waited > READY_TIMEOUT_SECONDS:
			Log.warn(&"world", "spawn terrain not ready after %.0f s, announcing anyway" % READY_TIMEOUT_SECONDS)
		var payload := _announcement
		_announcement = {}
		EventBus.publish(&"world.ready", payload)


func _on_player_spawned(p: Dictionary) -> void:
	var player: Node3D = p["player"]
	player.add_child(_voxels.make_viewer())


func _on_weapon_fired(p: Dictionary) -> void:
	if p.get("collider") is VoxelLodTerrain and float(p.get("damage", 0.0)) == 0.0:
		_voxels.server_dig(p["to"], BULLET_CRATER_RADIUS)
