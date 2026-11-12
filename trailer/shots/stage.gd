extends Node3D
## Base for trailer shots (tools/trailer.ts renders them through tools/gd/movie.gd). Boots the
## world, the modules a shot asks for and one local player, then hands each physics tick to
## `_shot(tick)`. A cinema camera moves between framings with eased dolly moves and a little
## hand-held sway, so shots are not static views.
##
## Modules are loaded by path, never by class name, so deleting a module only breaks the shots
## that use it, at render time.

const WORLD := "res://modules/world/scenes/world.tscn"
const PLAYER := "res://modules/player/scenes/player.tscn"
const MODULES := {
	"weapons": "res://modules/weapons/weapons_module.gd",
	"inventory": "res://modules/inventory/inventory_module.gd",
	"enemies": "res://modules/enemies/enemies_module.gd",
	"drones": "res://modules/drones/drones_module.gd",
	"missions": "res://modules/missions/missions_module.gd",
}
## Sway in metres and how fast it drifts; small enough to read as a held camera, not a shake.
const SWAY := 0.05
const SWAY_RATE := 0.6
## The camera never goes lower than this over the ground.
const CAM_CLEARANCE := 0.4
## Settling: the world's background builds must stay quiet this many ticks in a row, after at
## least MIN_SETTLE ticks and at most MAX_SETTLE.
const QUIET_TICKS := 30
const MIN_SETTLE := 60
const MAX_SETTLE := 1500
## A hit closer to the subject than this is the subject itself (its wall, its body).
const SUBJECT_SLACK := 3.0

var player: Node3D
var modules := {}
var cam: Camera3D
## Off for shots under the ground (the home tunnel), where the hill above is "the ground".
var keep_above_ground := true

var _tick := 0
var _ready_done := false
var _move_from: Transform3D
var _move_to: Transform3D
var _move_start := 0
var _move_frames := 0
var _look_target := Vector3.INF
var _noise := FastNoiseLite.new()
## What the camera is filming (the look point of the current framing), for the blocked check.
var _subject := Vector3.INF
## The thing being filmed, if it has collision of its own (a house): hits on it don't count.
var subject_body: Node
var _blocked_by := ""


## Override: the module ids this shot needs, in load order.
func _modules() -> Array[String]:
	return ["weapons", "inventory", "enemies", "missions"]


## Override: called once everything is up (start a mission here).
func _setup() -> void:
	pass


## Override: a tick after `_setup`: put people where they start and the camera on its first
## framing. The world then settles around the camera before the shot rolls.
func _place() -> void:
	pass


## Override: called every physics tick from 1.
func _shot(_t: int) -> void:
	pass


func _init() -> void:
	# tools/gd/movie.gd starts counting kept frames once this turns true.
	set_meta(&"rolling", false)


func _ready() -> void:
	await VoxelWorld.add_and_wait(self, WORLD)
	for id in _modules():
		var node: Node = (load(MODULES[id]) as GDScript).new()
		add_child(node)
		modules[id] = node
	EventBus.subscribe(&"player.move_requested", func(p: Dictionary) -> void: (p["player"] as Node3D).global_position = p["position"])
	var spawn := (get_tree().get_first_node_in_group(&"spawn_point") as Node3D).global_position
	player = (load(PLAYER) as PackedScene).instantiate()
	player.set_meta(&"peer_id", 1)
	player.add_to_group(&"players")
	add_child(player)
	player.global_position = spawn
	EventBus.publish(&"player.spawned", {"player": player, "local": true})
	EventBus.publish(&"world.ready", {"spawn": spawn})
	cam = Camera3D.new()
	cam.fov = 60.0
	add_child(cam)
	cam.current = true
	_noise.seed = 3
	_noise.frequency = 1.0
	_setup()
	await get_tree().physics_frame
	_place()
	_update_camera()
	await _settle()
	_ready_done = true
	set_meta(&"rolling", true)


## Waits until the ground and scenery around the camera are built: the background jobs of
## both stay empty for a while and the ground under the camera has collision.
func _settle() -> void:
	var terrain := get_tree().get_first_node_in_group(&"ground")
	var scenery := _find_scenery(get_tree().root)
	var quiet := 0
	for i in MAX_SETTLE:
		await get_tree().physics_frame
		_update_camera()
		var busy := false
		if terrain != null:
			busy = bool(terrain.get(&"_pending")) or not (terrain.get(&"_tile_jobs") as Dictionary).is_empty() or not bool(terrain.call(&"is_ready_at", cam.global_position, 16.0))
		if scenery != null:
			busy = busy or not (scenery.get(&"_pending") as Dictionary).is_empty()
		quiet = 0 if busy else quiet + 1
		if i >= MIN_SETTLE and quiet >= QUIET_TICKS:
			return
	push_warning("trailer: the world did not settle in %d ticks" % MAX_SETTLE)


func _is_subject(node: Node) -> bool:
	return subject_body != null and node != null and (node == subject_body or subject_body.is_ancestor_of(node))


func _find_scenery(node: Node) -> Node:
	if node.get(&"_pending") is Dictionary and node.has_method(&"loaded_chunks"):
		return node
	for child in node.get_children():
		var found := _find_scenery(child)
		if found != null:
			return found
	return null


func _physics_process(_delta: float) -> void:
	if not _ready_done:
		return
	_tick += 1
	_shot(_tick)
	_update_camera()
	_check_view()


## Says when something comes between the camera and its subject and when the view clears,
## so tools/trailer.ts can report blocked shots instead of someone spotting them by eye.
func _check_view() -> void:
	if _subject == Vector3.INF:
		return
	var from := cam.global_position
	var query := PhysicsRayQueryParameters3D.create(from, _subject)
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(query)
	var by := ""
	if not hit.is_empty() and (hit["position"] as Vector3).distance_to(_subject) > SUBJECT_SLACK and not _is_subject(hit["collider"] as Node):
		var collider := hit["collider"] as Node
		by = "%s/%s" % [collider.get_parent().name, collider.name] if collider != null and collider.get_parent() != null else "something"
	if by != _blocked_by:
		if by.is_empty():
			Log.info(&"trailer", "camera clear at tick %d" % _tick)
		else:
			Log.info(&"trailer", "camera blocked at tick %d by %s" % [_tick, by])
		_blocked_by = by


## Puts the camera at `from` looking at `look` now.
func frame(from: Vector3, look: Vector3) -> void:
	_move_from = Transform3D.IDENTITY.looking_at(look - from, Vector3.UP)
	_move_from.origin = from
	_move_to = _move_from
	_move_frames = 0
	_subject = look


## Eases the camera from where it is to `to`, looking at `look`, over `frames` ticks.
func move_to(to: Vector3, look: Vector3, frames: int) -> void:
	_move_from = cam.global_transform
	_move_to = Transform3D.IDENTITY.looking_at(look - to, Vector3.UP)
	_move_to.origin = to
	_move_start = _tick
	_move_frames = frames
	_subject = look


## Keeps the camera turned on `target` wherever it moves; Vector3.INF stops that.
func track(target: Vector3) -> void:
	_look_target = target
	if target != Vector3.INF:
		_subject = target


## Makes the local player face `at` from where it stands.
func face(at: Vector3) -> void:
	var p := player.global_position
	player.look_at(Vector3(at.x, p.y, at.z), Vector3.UP)


## Keeps trees and rocks off the line from `from` to `to` (circles of `radius` every few
## metres), so nothing grows between the camera and what it films. Call it from `_place`:
## the settle that follows waits for the rebuilt scenery.
func clear_line(from: Vector3, to: Vector3, radius: float = 3.0) -> void:
	var scenery := _find_scenery(get_tree().root)
	if scenery == null:
		return
	var circles: Array = []
	for c: Vector3 in scenery.get(&"_clearings"):
		circles.append({"at": Vector3(c.x, 0.0, c.y), "radius": c.z})
	var steps := maxi(1, ceili(from.distance_to(to) / (radius * 1.2)))
	for i in steps + 1:
		circles.append({"at": from.lerp(to, float(i) / float(steps)), "radius": radius})
	scenery.call(&"set_clearings", circles)


func mission() -> Node:
	return modules.get("missions")


## Picks the first offer of `type` the board rolls and rides out to it.
func start_mission(type: String) -> void:
	var missions := mission()
	var cfg: Dictionary = missions.get(&"config")
	for seed_value in 80:
		var offers: Array = missions.call(&"roll_offers", cfg, seed_value)
		var found := offers.filter(func(o: Dictionary) -> bool: return o["type"] == type)
		if not found.is_empty():
			missions.set(&"offers", offers)
			missions.call(&"server_choose", 1, offers.find(found[0]))
			break
	missions.call(&"server_ride_out")


func ground_y(x: float, z: float) -> float:
	return float(mission().call(&"ground_y", x, z))


func _update_camera() -> void:
	var t := 1.0
	if _move_frames > 0:
		t = clampf(float(_tick - _move_start) / float(_move_frames), 0.0, 1.0)
	var eased := t * t * (3.0 - 2.0 * t)
	var xf := _move_from.interpolate_with(_move_to, eased)
	var time := float(_tick) / 60.0 * SWAY_RATE
	xf.origin += Vector3(_noise.get_noise_2d(time, 0.0), _noise.get_noise_2d(0.0, time), _noise.get_noise_2d(time, time)) * SWAY
	if keep_above_ground and modules.has("missions"):
		xf.origin.y = maxf(xf.origin.y, ground_y(xf.origin.x, xf.origin.z) + CAM_CLEARANCE)
	if _look_target != Vector3.INF and xf.origin.distance_to(_look_target) > 0.1:
		xf = xf.looking_at(_look_target, Vector3.UP)
	cam.global_transform = xf
