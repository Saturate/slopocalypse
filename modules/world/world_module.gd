extends Node
## Loads the world, waits until the ground around the spawn has collision, then announces
## it. Also owns terrain-side reactions: shots that hit the ground dig a small crater, and
## explosions a big one. The ground follows players, enemies and vehicles on its own.

const SCENE := "res://modules/world/scenes/world.tscn"
const CONFIG := "res://modules/world/data/world.json"
## Give up waiting for the spawn area after this long rather than hang a headless server.
const READY_TIMEOUT_SECONDS := 30.0
const BULLET_CRATER_RADIUS := 0.35
const SPAWN_AREA_RADIUS := 16.0

var _voxels: VoxelWorld
var _scenery: SceneryScatter
var _announcement: Dictionary = {}
var _waited := 0.0


func _ready() -> void:
	var data: Variant = Data.load_json(CONFIG)
	if not data is Dictionary or not Data.require(CONFIG, data, {"kill_y": TYPE_FLOAT, "rescue_depth": TYPE_FLOAT}):
		return
	var scene: PackedScene = load(SCENE)
	var world := scene.instantiate()
	add_child(world)
	_voxels = world.get_node("Terrain")
	_scenery = world.get_node("Scenery")
	_voxels.dug.connect(_scenery.on_dug)
	var spawn: Marker3D = world.get_node("SpawnPoint")
	var car: Marker3D = world.get_node("CarSpawn")
	# `front` and `forward`: players start inside the tunnel, so things spread "around the
	# spawn" (crates, enemies) go around the road just outside it, on the open side.
	_announcement = {
		"spawn": spawn.global_position,
		"car": car.global_transform,
		"front": Vector3(car.global_position.x, spawn.global_position.y, car.global_position.z),
		"forward": Vector3.FORWARD,
		"kill_y": data["kill_y"],
		"rescue_depth": data["rescue_depth"],
	}
	EventBus.subscribe(&"weapon.fired", _on_weapon_fired)
	EventBus.subscribe(&"explosion", _on_explosion)
	EventBus.subscribe(&"world.tree_felled", _on_tree_felled)
	Net.peer_joined.connect(_on_peer_joined)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"weapon.fired", _on_weapon_fired)
	EventBus.unsubscribe(&"explosion", _on_explosion)
	EventBus.unsubscribe(&"world.tree_felled", _on_tree_felled)
	if Net.peer_joined.is_connected(_on_peer_joined):
		Net.peer_joined.disconnect(_on_peer_joined)


func _on_explosion(p: Dictionary) -> void:
	_voxels.server_dig(p["position"], float(p["radius"]))
	if _is_server():
		var blasted := _scenery.server_blast_trees(p["position"], float(p["radius"]))
		for id: Vector2i in blasted:
			var hit: Dictionary = blasted[id]
			_broadcast_fell(id, hit["direction"], hit["cut"], hit["blast"])


func _is_server() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()


func _broadcast_fell(id: Vector2i, direction: Vector3, cut: float, blast: Vector4 = Vector4.ZERO) -> void:
	Net.server_broadcast(&"world.tree_felled", {"chunk": id.x, "index": id.y, "direction": direction, "cut": cut, "blast": blast})


func _on_tree_felled(p: Dictionary) -> void:
	_scenery.fell_tree(Vector2i(int(p["chunk"]), int(p["index"])), p["direction"], float(p.get("cut", 1.0)), p.get("blast", Vector4.ZERO))


## Someone joining late gets every tree already down, lying where it fell.
func _on_peer_joined(peer: int) -> void:
	if not _is_server():
		return
	var felled := _scenery.felled()
	if felled.is_empty():
		return
	var list: Array = []
	for id: Vector2i in felled:
		var info: Dictionary = felled[id]
		list.append([id.x, id.y, info["direction"], info["cut"], info["blast"]])
	_receive_felled.rpc_id(peer, list)


@rpc("authority", "call_remote", "reliable")
func _receive_felled(list: Array) -> void:
	for entry: Array in list:
		_scenery.fell_tree(Vector2i(int(entry[0]), int(entry[1])), entry[2], float(entry[3]), entry[4])


func _process(delta: float) -> void:
	if _announcement.is_empty():
		return
	_waited += delta
	var spawn: Vector3 = _announcement["spawn"]
	# Meshes can be ready a frame or two before their collision, and things spawn up to ~8 m
	# from the spawn point (the car), so wait for a wider area and a real physics hit.
	var ready := _voxels.is_ready_at(spawn, SPAWN_AREA_RADIUS) and _ground_hit(spawn)
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
