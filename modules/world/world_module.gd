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
	_voxels.dug.connect((world.get_node("Scenery") as SceneryScatter).clear_grass)
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


func _exit_tree() -> void:
	EventBus.unsubscribe(&"weapon.fired", _on_weapon_fired)
	EventBus.unsubscribe(&"explosion", _on_explosion)


func _on_explosion(p: Dictionary) -> void:
	_voxels.server_dig(p["position"], float(p["radius"]))


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
	if hit is Node and (hit as Node).is_in_group(&"terrain") and float(p.get("damage", 0.0)) == 0.0:
		_voxels.server_dig(p["to"], BULLET_CRATER_RADIUS)
