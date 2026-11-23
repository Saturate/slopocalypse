extends Node3D
## Capture setup: what hangs on a body posed less often (BodyLod) still follows it. At 7, 20
## and 45 m from a still camera: a civilian with an armband and a lit glowstick on the chest
## walks back and forth, a soldier climbs a ladder up and down on a wall, and a third body
## stands until `DIE_TICK` and then falls as a ragdoll. Capture about 300 frames.

const WORLD := "res://modules/world/scenes/world.tscn"
const PLAYER := "res://modules/player/scenes/player.tscn"
const WEAPONS := "res://modules/weapons/weapons_module.gd"
const ROWS := [7.0, 20.0, 45.0]
## Out past the underpass at the spawn, on open ground.
const ORIGIN := Vector3(0.0, 0.0, -40.0)
const WALK_SPEED := 1.6
const CLIMB_SPEED := 0.8
## Each walker walks this far either side of where it started, then turns.
const REACH := 3.0
## The climbers' wall: how high, and how high they climb on it before coming back down.
const WALL_HEIGHT := 4.0
const CLIMB_HEIGHT := 2.4
const DIE_TICK := 150

var _walkers: Array[PlayerController] = []
var _climbers: Array[PlayerController] = []
var _fallers: Array[PlayerController] = []
var _camera := Camera3D.new()
var _world: Node
var _t := 0.0
var _ticks := 0


func _ready() -> void:
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	_world = world.get_node_or_null("Terrain")
	var scenery := find_child("Scenery", true, false) as Node3D
	if scenery != null:
		scenery.visible = false
	Corpse.enabled = true
	Armband.enabled = true
	add_child((load(WEAPONS) as GDScript).new())
	add_child(_camera)
	_camera.fov = BodyLod.shared().reference_fov
	_camera.global_position = ORIGIN + Vector3(0.0, _ground(ORIGIN.x, ORIGIN.z) + 1.7, 0.0)
	_camera.current = true
	var sticks: Variant = Data.load_json(GlowstickRules.CONFIG)
	var peer := 50
	for row: float in ROWS:
		var z := ORIGIN.z - row
		peer += 1
		var walker := _body(peer)
		walker.set_meta(&"civilian", true)
		Armband.apply(walker)
		if sticks is Dictionary:
			_hold_stick(walker, sticks)
		walker.set_meta(&"row_z", z)
		_walkers.append(walker)
		peer += 1
		var climber := _body(peer)
		climber.set_meta(&"team", 1)
		Armband.apply(climber)
		var foot := Vector3(ORIGIN.x - 4.0 - row * 0.08, _ground(ORIGIN.x - 4.0 - row * 0.08, z), z)
		_ladder(foot)
		climber.global_position = foot
		climber.set_meta(&"foot", foot)
		climber.climbing = true
		_climbers.append(climber)
		peer += 1
		var faller := _body(peer)
		faller.set_meta(&"team", 1)
		Armband.apply(faller)
		var spot := Vector3(ORIGIN.x + 3.5 + row * 0.08, 0.0, z)
		spot.y = _ground(spot.x, spot.z)
		faller.global_position = spot
		_fallers.append(faller)


func _body(peer: int) -> PlayerController:
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
	return body


## A lit stick on the chest bone, held the way the glowsticks module holds one.
func _hold_stick(person: PlayerController, cfg: Dictionary) -> void:
	var skeleton := person.get_node("Body/Skeleton") as Skeleton3D
	var holder := BoneAttachment3D.new()
	holder.bone_name = "Chest"
	skeleton.add_child(holder)
	var colour := Color(0.3, 1.0, 0.4)
	var mesh := GlowstickView.stick(cfg, colour, float(cfg["stick"]["glow"]))
	var at: Array = cfg["stick"]["at"]
	mesh.position = Vector3(float(at[0]), float(at[1]), float(at[2]))
	holder.add_child(mesh)
	var glow := GlowstickView.halo(cfg["stick"], colour)
	glow.position = mesh.position + Vector3(0.0, 0.0, -0.06)
	holder.add_child(glow)


## A wall facing the camera with a ladder box on its front, like a ladder on a building.
func _ladder(foot: Vector3) -> void:
	var wall := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.6, WALL_HEIGHT, 0.3)
	wall.mesh = box
	add_child(wall)
	wall.global_position = foot + Vector3(0.0, WALL_HEIGHT / 2.0, -0.55)
	# Climbers face -Z, into the wall.
	Ladders.add(wall, Transform3D(Basis.IDENTITY, foot + Vector3(0.0, WALL_HEIGHT / 2.0, -0.1)), Vector3(0.4, WALL_HEIGHT / 2.0, 0.4), Vector3.FORWARD)


func _ground(x: float, z: float) -> float:
	if _world != null and _world.has_method(&"ground_height"):
		return float(_world.call(&"ground_height", x, z))
	return 0.0


func _physics_process(delta: float) -> void:
	if _walkers.is_empty():
		return
	_t += delta
	_ticks += 1
	for body in _walkers:
		var z := float(body.get_meta(&"row_z"))
		var phase := fposmod(_t * WALK_SPEED / (4.0 * REACH) + 0.25, 1.0)
		var x := (4.0 * absf(phase - 0.5) - 1.0) * REACH
		var heading := -signf(phase - 0.5)
		body.global_position = Vector3(ORIGIN.x + x, _ground(ORIGIN.x + x, z), z)
		body.velocity = Vector3(heading * WALK_SPEED, 0.0, 0.0)
		body.rotation.y = -PI / 2.0 if heading > 0.0 else PI / 2.0
	for body in _climbers:
		var foot: Vector3 = body.get_meta(&"foot")
		var phase := fposmod(_t * CLIMB_SPEED / (2.0 * CLIMB_HEIGHT), 1.0)
		var up := 1.0 - 2.0 * absf(phase - 0.5)
		body.global_position = foot + Vector3.UP * up * CLIMB_HEIGHT
		body.velocity = Vector3.UP * CLIMB_SPEED * (1.0 if phase < 0.5 else -1.0)
	if _ticks == DIE_TICK:
		for body in _fallers:
			Corpse.from_body(body, Vector3(0.0, float(Corpse.config()["push_up"]), float(Corpse.config()["push"])))
			(body.get_node("Body") as Node3D).visible = false
