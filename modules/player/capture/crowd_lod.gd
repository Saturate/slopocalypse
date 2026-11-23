extends Node3D
## Capture setup: armed copies of other bodies walk back and forth across the view at 7, 20
## and 45 m (posed every frame, `mid_rate` and `far_rate` times a second by BodyLod), seen
## from a still camera at eye height, so a reviewer can judge whether the poses hold up.

const WORLD := "res://modules/world/scenes/world.tscn"
const PLAYER := "res://modules/player/scenes/player.tscn"
const WEAPONS := "res://modules/weapons/weapons_module.gd"
const ROWS := [7.0, 20.0, 45.0]

## Out past the underpass at the spawn, on open ground.
const ORIGIN := Vector3(0.0, 0.0, -40.0)
const WALK_SPEED := 1.6
## Each walks this far either side of where it started, then turns.
const REACH := 5.0

var _bodies: Array[PlayerController] = []
var _starts: Array[float] = []
var _camera := Camera3D.new()
var _world: Node
var _t := 0.0


func _ready() -> void:
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	_world = world.get_node_or_null("Terrain")
	var scenery := find_child("Scenery", true, false) as Node3D
	if scenery != null:
		scenery.visible = false
	add_child((load(WEAPONS) as GDScript).new())
	add_child(_camera)
	# The field of view distances are judged at, so the rows land in the every-frame, mid and
	# far bands as named.
	_camera.fov = BodyLod.shared().reference_fov
	_camera.global_position = ORIGIN + Vector3(0.0, _ground(ORIGIN.x, ORIGIN.z) + 1.7, 0.0)
	_camera.current = true
	var peer := 50
	for row: float in ROWS:
		for i in 2:
			peer += 1
			var body: PlayerController = (load(PLAYER) as PackedScene).instantiate()
			body.set_meta(&"peer_id", peer)
			body.add_to_group(&"players")
			# Moved here like a client moves someone else's copy: no physics of its own.
			PlayerController.hold_still(body)
			add_child(body)
			_camera.current = true
			EventBus.publish(&"player.spawned", {"player": body, "local": false})
			var animator := PlayerBodyAnimator.new()
			animator.name = "BodyAnimator"
			animator.player = body
			animator.lod = true
			body.add_child(animator)
			_bodies.append(body)
			# Two to a row, 4 m apart in depth so they never seem to walk through each other.
			_starts.append(-REACH * 0.5 + row * 0.3 if i == 0 else REACH * 0.5 + row * 0.7)
			body.set_meta(&"capture_z", ORIGIN.z - row - 4.0 * i)
			body.set_meta(&"capture_way", 1.0 if i == 0 else -1.0)


func _ground(x: float, z: float) -> float:
	if _world != null and _world.has_method(&"ground_height"):
		return float(_world.call(&"ground_height", x, z))
	return 0.0


func _physics_process(delta: float) -> void:
	if _bodies.is_empty():
		return
	_t += delta
	for i in _bodies.size():
		var body := _bodies[i]
		var way := float(body.get_meta(&"capture_way"))
		# Back and forth across the view: a triangle wave in x.
		var phase := fposmod(_t * WALK_SPEED / (4.0 * REACH) + 0.25 + _starts[i] / (4.0 * REACH), 1.0)
		var x := (4.0 * absf(phase - 0.5) - 1.0) * REACH * way
		var heading := -signf(phase - 0.5) * way
		var z := float(body.get_meta(&"capture_z"))
		body.global_position = Vector3(ORIGIN.x + x, _ground(ORIGIN.x + x, z), z)
		body.velocity = Vector3(heading * WALK_SPEED, 0.0, 0.0)
		# Faces the way it walks (the body looks down -Z).
		body.rotation.y = -PI / 2.0 if heading > 0.0 else PI / 2.0
