extends Node3D
## Capture setup (#447): glowsticks at night. From eye height across open ground: a co-op
## partner about 40 m off with a cracked glowstick, and a patrol of three militia soldiers a
## little further, one of them showing theirs; they turn slowly. With `-- --inside`, inside
## a closed plaster room (5 x 5 m, 2.6 m high) instead: a player with a lit stick near the
## back wall, who stows it from frame `STOW_FRAME` on, to show how much of the room it
## lights (capture 300 frames, 4 to the sheet: two lit, two stowed).

const WORLD := "res://modules/world/scenes/world.tscn"
const PLAYER := "res://modules/player/scenes/player.tscn"
const WEAPONS := "res://modules/weapons/weapons_module.gd"
const ENEMIES := "res://modules/enemies/enemies_module.gd"
const FACTIONS := "res://modules/factions/factions_module.gd"
const INVENTORY := "res://modules/inventory/inventory_module.gd"
const GLOWSTICKS := "res://modules/glowsticks/glowsticks_module.gd"
const NIGHT := 23.0
const STOW_FRAME := 190
const TURN := 1.0
const ROOM := Vector3(30.0, 0.0, 12.0)
const ROOM_SIZE := Vector3(5.0, 2.6, 5.0)
const WALL := 0.2

var _people: Array[Node3D] = []
var _clock: DayClock
var _lighting := DayLighting.new()
var _camera: Camera3D
var _inside: PlayerController
var _ticks := 0
var _indoors := false
var _glowsticks: Node


## Stands in for the day and night module the glowsticks ask whether it is night.
func clock() -> DayClock:
	return _clock


func _ready() -> void:
	add_to_group(&"daytime_api")
	_indoors = OS.get_cmdline_user_args().has("--inside")
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	var terrain := world.get_node("Terrain") as VoxelWorld
	var scenery := find_child("Scenery", true, false) as Node3D
	if scenery != null:
		scenery.visible = false
	_clock = DayClock.from_data()
	add_child(_lighting)
	var env := world.get_node("Environment") as WorldEnvironment
	_lighting.attach(world.get_node("Sun") as DirectionalLight3D, env.environment)
	_clock.set_hour(NIGHT)
	_lighting.apply(_clock)

	var eye := VoxelWorld.spawn_of(world, Vector3(0.0, 1.65, 0.0))
	var target := VoxelWorld.spawn_of(world, Vector3(0.0, 0.0, -42.0))
	var room := VoxelWorld.spawn_of(world, ROOM)
	terrain.update_around([eye, target, room], INF)
	for i in 600:
		if terrain.is_ready_at(target, 10.0) and terrain.is_ready_at(room, 6.0):
			break
		await get_tree().physics_frame

	add_child((load(WEAPONS) as GDScript).new())
	add_child((load(FACTIONS) as GDScript).new())
	var inventory: Node = (load(INVENTORY) as GDScript).new()
	add_child(inventory)
	var glowsticks: Node = (load(GLOWSTICKS) as GDScript).new()
	_glowsticks = glowsticks
	add_child(glowsticks)
	var enemies: Node = (load(ENEMIES) as GDScript).new()
	add_child(enemies)

	_camera = Camera3D.new()
	_camera.fov = 70.0
	_camera.far = 900.0
	add_child(_camera)
	_camera.current = true
	_camera.global_position = eye
	_camera.look_at(target + Vector3.UP * 1.1)
	_camera.add_child(terrain.make_viewer())

	var partner := _player(2, VoxelWorld.spawn_of(world, Vector3(-4.0, 0.1, -40.0)))
	inventory.call(&"server_give", 2, GlowstickRules.ITEM)
	glowsticks.call(&"server_crack", 2)
	_people.append(partner)

	var cfg: Dictionary = glowsticks.get(&"config")
	var share := float(cfg["enemy_night_share"])
	for i in 3:
		cfg["enemy_night_share"] = 1.0 if i == 1 else 0.0
		var at := VoxelWorld.spawn_of(world, Vector3(2.0 + float(i) * 2.2, 0.1, -46.0 - float(i % 2)))
		_people.append(enemies.call(&"server_spawn_guard", at, 0.0, [], "militia"))
	cfg["enemy_night_share"] = share

	# Lit from inside only, so any light on its walls is the stick's.
	# On a plinth over the highest corner, so no grass pokes through the floor.
	var floor_at := room
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		floor_at.y = maxf(floor_at.y, terrain.ground_height(room.x + corner.x * ROOM_SIZE.x / 2.0, room.z + corner.y * ROOM_SIZE.z / 2.0) + 0.05)
	_build_room(floor_at)
	_inside = _player(3, floor_at + Vector3(0.0, 0.1, -ROOM_SIZE.z / 2.0 + 0.9))
	inventory.call(&"server_give", 3, GlowstickRules.ITEM)
	glowsticks.call(&"server_crack", 3)
	if _indoors:
		_camera.global_position = floor_at + Vector3(ROOM_SIZE.x / 2.0 - 0.7, 1.7, ROOM_SIZE.z / 2.0 - 0.7)
		_camera.look_at(floor_at + Vector3(-0.6, 0.9, -ROOM_SIZE.z / 2.0))

	# They stand for the picture: each brain is paused while still on patrol, so it neither
	# walks them off nor stops counting as patrolling.
	await get_tree().process_frame
	for person in _people:
		var brain := person.get_node_or_null("Brain")
		if brain != null:
			brain.process_mode = Node.PROCESS_MODE_DISABLED
		(person as PlayerController).intent().move = Vector2.ZERO


func _player(peer: int, at: Vector3) -> PlayerController:
	var p: PlayerController = (load(PLAYER) as PackedScene).instantiate()
	p.name = "Player%d" % peer
	p.set_meta(&"peer_id", peer)
	p.add_to_group(&"players")
	add_child(p)
	p.global_position = at
	EventBus.publish(&"player.spawned", {"player": p, "local": false})
	var animator := PlayerBodyAnimator.new()
	animator.player = p
	p.add_child(animator)
	return p


func _build_room(floor_at: Vector3) -> void:
	var plaster := StandardMaterial3D.new()
	plaster.albedo_color = Color(0.62, 0.6, 0.56)
	plaster.roughness = 0.9
	var half := ROOM_SIZE / 2.0
	var parts: Array[AABB] = [
		AABB(Vector3(-half.x - WALL, -WALL, -half.z - WALL), Vector3(ROOM_SIZE.x + WALL * 2.0, WALL, ROOM_SIZE.z + WALL * 2.0)),
		AABB(Vector3(-half.x - WALL, ROOM_SIZE.y, -half.z - WALL), Vector3(ROOM_SIZE.x + WALL * 2.0, WALL, ROOM_SIZE.z + WALL * 2.0)),
		AABB(Vector3(-half.x - WALL, 0.0, -half.z - WALL), Vector3(WALL, ROOM_SIZE.y, ROOM_SIZE.z + WALL * 2.0)),
		AABB(Vector3(half.x, 0.0, -half.z - WALL), Vector3(WALL, ROOM_SIZE.y, ROOM_SIZE.z + WALL * 2.0)),
		AABB(Vector3(-half.x, 0.0, -half.z - WALL), Vector3(ROOM_SIZE.x, ROOM_SIZE.y, WALL)),
		AABB(Vector3(-half.x, 0.0, half.z), Vector3(ROOM_SIZE.x, ROOM_SIZE.y, WALL)),
	]
	for box in parts:
		var body := StaticBody3D.new()
		add_child(body)
		body.global_position = floor_at + box.get_center()
		var shape := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = box.size
		shape.shape = b
		body.add_child(shape)
		var mesh := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = box.size
		m.material = plaster
		mesh.mesh = m
		body.add_child(mesh)


func _physics_process(_delta: float) -> void:
	if _people.is_empty() or _camera == null:
		return
	_ticks += 1
	for i in _people.size():
		var person := _people[i] as PlayerController
		if person != null:
			var yaw := deg_to_rad(float(_ticks) * TURN + float(i) * 70.0)
			person.intent().look_yaw = yaw
			person.rotation.y = yaw
	# Facing the camera's corner of the room.
	_inside.intent().look_yaw = deg_to_rad(150.0)
	_inside.rotation.y = deg_to_rad(150.0)
	if _indoors and Engine.get_process_frames() >= STOW_FRAME and bool((_glowsticks.call(&"lit_of", 3) as Dictionary).get("shown", false)):
		_glowsticks.call(&"server_stow", 3, true)
