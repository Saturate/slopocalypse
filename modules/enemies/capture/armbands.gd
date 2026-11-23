extends Node3D
## Capture setup (#447): from eye height, a co-op player, a civilian, a regular, a militia
## soldier and a scavenger stand in a row about 30 m away, turning slowly so their armbands
## are seen from every side; noon first, then night. `-- --hour=H` holds one hour instead
## (for a full-size single frame); `-- --colour-blind` shows the colour-blind colours.

const WORLD := "res://modules/world/scenes/world.tscn"
const PLAYER := "res://modules/player/scenes/player.tscn"
const WEAPONS := "res://modules/weapons/weapons_module.gd"
const ENEMIES := "res://modules/enemies/enemies_module.gd"
const FACTIONS := "res://modules/factions/factions_module.gd"
const DISTANCE := 30.0
const SPACING := 2.5
const NOON := 13.0
const NIGHT := 23.0
## Frame the noon shots end on.
const NIGHT_FROM := 190
## Degrees a frame the row turns.
const TURN := 1.0

var _people: Array[Node3D] = []
var _clock: DayClock
var _lighting := DayLighting.new()
var _ticks := 0
var _hour := -1.0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hour="):
			_hour = float(arg.trim_prefix("--hour="))
	Settings.set_value(Armband.SETTING, OS.get_cmdline_user_args().has("--colour-blind"))
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	var terrain := world.get_node("Terrain") as VoxelWorld
	var scenery := find_child("Scenery", true, false) as Node3D
	if scenery != null:
		scenery.visible = false
	_clock = DayClock.from_data()
	add_child(_lighting)
	var env := world.get_node("Environment") as WorldEnvironment
	_lighting.attach(world.get_node("Sun") as DirectionalLight3D, env.environment)
	_clock.set_hour(NOON if _hour < 0.0 else _hour)
	_lighting.apply(_clock)

	var eye := VoxelWorld.spawn_of(world, Vector3(0.0, 1.65, 0.0))
	var target := VoxelWorld.spawn_of(world, Vector3(0.0, 0.0, -DISTANCE))
	terrain.update_around([eye, target], INF)
	for i in 600:
		if terrain.is_ready_at(target, 10.0):
			break
		await get_tree().physics_frame

	add_child((load(WEAPONS) as GDScript).new())
	add_child((load(FACTIONS) as GDScript).new())
	var enemies: Node = (load(ENEMIES) as GDScript).new()
	add_child(enemies)

	var camera := Camera3D.new()
	camera.fov = 80.0
	camera.far = 900.0
	add_child(camera)
	camera.current = true
	camera.global_position = eye
	camera.look_at(target + Vector3.UP * 1.1)
	camera.add_child(terrain.make_viewer())

	var spots: Array[Vector3] = []
	for i in 5:
		spots.append(VoxelWorld.spawn_of(world, Vector3((float(i) - 2.0) * SPACING, 0.1, -DISTANCE)))
	# A co-op partner: someone else's player body, as a client sees it.
	var partner: PlayerController = (load(PLAYER) as PackedScene).instantiate()
	partner.name = "Partner"
	add_child(partner)
	partner.global_position = spots[0]
	EventBus.publish(&"player.spawned", {"player": partner, "local": false})
	var animator := PlayerBodyAnimator.new()
	animator.player = partner
	partner.add_child(animator)
	_people.append(partner)
	_people.append(enemies.call(&"server_spawn_civilian", spots[1], 0.0, []))
	_people.append(enemies.call(&"server_spawn_guard", spots[2], 0.0, [], "regulars"))
	_people.append(enemies.call(&"server_spawn_guard", spots[3], 0.0, [], "militia"))
	_people.append(enemies.call(&"server_spawn_guard", spots[4], 0.0, [], "scavengers"))
	# They stand for the picture: no brain walks them off or turns them to fight.
	await get_tree().process_frame
	for person in _people:
		var brain := person.get_node_or_null("Brain")
		if brain != null:
			brain.queue_free()
		# A step the brain asked for would carry on without it.
		(person as PlayerController).intent().move = Vector2.ZERO


func _physics_process(_delta: float) -> void:
	if _people.is_empty():
		return
	_ticks += 1
	for i in _people.size():
		var person := _people[i] as PlayerController
		if person != null:
			var yaw := deg_to_rad(float(_ticks) * TURN + float(i) * 45.0)
			# A body driven by a remote intent faces its intent's yaw.
			person.intent().look_yaw = yaw
			person.rotation.y = yaw
	if _hour < 0.0 and _ticks == NIGHT_FROM:
		_clock.set_hour(NIGHT)
		_lighting.apply(_clock)
