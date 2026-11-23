extends Node3D
## Capture setup: first person, a squad of three soldiers 20 m ahead (one of them the gunner,
## with the machine gun) fires on the player standing beside a chest-high wall; the player
## steps left behind it, and the gunner keeps firing at where they were, rounds hitting the
## wall and passing close, for a few seconds, then stops. The player can't be hurt. Run it
## with --frames 300 (the squad takes a couple of seconds to react before it opens up).

const WORLD := "res://modules/world/scenes/world.tscn"
const PLAYER := "res://modules/player/scenes/player.tscn"
const WEAPONS := "res://modules/weapons/weapons_module.gd"
const ENEMIES := "res://modules/enemies/enemies_module.gd"
## Physics ticks (two to each captured frame) before the player steps behind the wall.
const DUCK_TICK := 200
## How far the player steps left, to behind the wall's middle.
const STEP := 2.6

var _player: PlayerController
var _start := Vector3.ZERO
var _ticks := 0


func _ready() -> void:
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	var scenery := find_child("Scenery", true, false) as Node3D
	if scenery != null:
		scenery.visible = false
	var weapons: Node = (load(WEAPONS) as GDScript).new()
	add_child(weapons)
	var enemies: Node = (load(ENEMIES) as GDScript).new()
	add_child(enemies)
	# Brave, so the capture shows the gunner at work and not a soldier losing its nerve.
	((enemies.get(&"config") as Dictionary)["fortitude"] as Dictionary)["start"] = [20, 20]
	# Fighting where they stand: on rolling ground they would run off to a dip that hides them
	# from the player, and the shots would go into the ground at their feet, out of view.
	((enemies.get(&"config") as Dictionary)["cover"] as Dictionary)["search_radius"] = 0.0
	_player = (load(PLAYER) as PackedScene).instantiate()
	_player.set_meta(&"peer_id", 1)
	_player.add_to_group(&"players")
	add_child(_player)
	_start = VoxelWorld.spawn_of(world, Vector3(0.6, 0.5, 0.0))
	_player.global_position = _start
	EventBus.publish(&"player.spawned", {"player": _player, "local": true})
	(_player.get_node("Health") as HealthComponent).invulnerable = true
	var animator := PlayerBodyAnimator.new()
	animator.name = "BodyAnimator"
	animator.player = _player
	_player.add_child(animator)
	PlayerBody.first_person(_player.get_node("Body"))
	(_player.get_node("Head/Camera") as Camera3D).current = true
	var hud := PlayerHud.new()
	hud.player = _player
	_player.add_child(hud)
	_wall(VoxelWorld.spawn_of(world, Vector3(-2.0, 0.0, -1.5)))
	# The squad's last soldier is the gunner. Its gun is set before it spawns, so it comes
	# loaded instead of swapping guns (which starts a reload).
	var gunner_peer := int((load(ENEMIES) as GDScript).get_script_constant_map()["FIRST_ID"]) - (int(enemies.get(&"_spawned")) + 3)
	EventBus.publish(&"weapons.build_changed", {"peer": gunner_peer, "slot": "primary", "build": GunAssembly.build("mg_standard")})
	var squad: Array[Node] = enemies.call(&"server_spawn_squad", 3, VoxelWorld.spawn_of(world, Vector3(2.0, 0.0, -20.0)))
	# Think as often as a real server lets soldiers this near a player (BrainSleep's `think`).
	var near_seconds := float(((Data.load_json(BrainSleep.CONFIG) as Dictionary)["think"] as Dictionary)["near_seconds"])
	for body in squad:
		var brain := body.get_node("Brain") as EnemyBrain
		brain.set_think_every(near_seconds)
		# Facing the player, so the fight starts before the step instead of after a look round.
		(body as Node3D).rotation.y = PI
		brain.set(&"_yaw", PI)
		brain.set(&"_want_yaw", PI)
	(squad[-1].get_node("Brain") as EnemyBrain).gunner = true


## A chest-high block wall: it hides a standing player's chest from the squad while their eyes
## still see over it.
func _wall(at: Vector3) -> void:
	var size := Vector3(3.0, 1.5, 0.35)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.53, 0.5)
	cube.material = mat
	mesh.mesh = cube
	body.add_child(mesh)
	add_child(body)
	body.global_position = at + Vector3.UP * (size.y / 2.0 - 0.1)


func _physics_process(_delta: float) -> void:
	if _player == null:
		return
	_ticks += 1
	var intent := _player.intent()
	# Step left behind the wall, then stay there.
	intent.move = Vector2(-1.0, 0.0) if _ticks > DUCK_TICK and _player.global_position.x > _start.x - STEP else Vector2.ZERO
