extends Node3D
## Capture setup (#447): your own glowstick at night, in first person. You stand with the
## rifle at the hip and a lit stick on your chest, looking along open ground at a stick a
## partner dropped a few metres ahead. The view turns slowly left and right and dips toward
## your feet, so the sheet shows the gun, the ground at your feet and the dropped stick.

const WORLD := "res://modules/world/scenes/world.tscn"
const PLAYER := "res://modules/player/scenes/player.tscn"
const WEAPONS := "res://modules/weapons/weapons_module.gd"
const FACTIONS := "res://modules/factions/factions_module.gd"
const INVENTORY := "res://modules/inventory/inventory_module.gd"
const GLOWSTICKS := "res://modules/glowsticks/glowsticks_module.gd"
const NIGHT := 23.0
## Metres ahead of you the partner's stick lands.
const DROP_AHEAD := 3.5

var _clock: DayClock
var _lighting := DayLighting.new()
var _player: PlayerController
var _ticks := 0


## Stands in for the day and night module the glowsticks ask whether it is night.
func clock() -> DayClock:
	return _clock


func _ready() -> void:
	add_to_group(&"daytime_api")
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	var scenery := find_child("Scenery", true, false) as Node3D
	if scenery != null:
		scenery.visible = false
	_clock = DayClock.from_data()
	add_child(_lighting)
	var env := world.get_node("Environment") as WorldEnvironment
	_lighting.attach(world.get_node("Sun") as DirectionalLight3D, env.environment)
	_clock.set_hour(NIGHT)
	_lighting.apply(_clock)

	add_child((load(WEAPONS) as GDScript).new())
	add_child((load(FACTIONS) as GDScript).new())
	var inventory: Node = (load(INVENTORY) as GDScript).new()
	add_child(inventory)
	var glowsticks: Node = (load(GLOWSTICKS) as GDScript).new()
	add_child(glowsticks)

	# Offline, this instance is peer 1: the stick on peer 1 is drawn as your own.
	_player = _spawn(1, VoxelWorld.spawn_of(world, Vector3(0.0, 0.1, 0.0)), true)
	PlayerBody.first_person(_player.get_node("Body"))
	(_player.get_node("Head/Camera") as Camera3D).current = true
	inventory.call(&"server_give", 1, GlowstickRules.ITEM)
	glowsticks.call(&"server_crack", 1)

	# The partner cracks theirs, drops it ahead of you and walks off out of the picture.
	var partner := _spawn(2, VoxelWorld.spawn_of(world, Vector3(0.0, 0.1, -DROP_AHEAD - 0.4)), false)
	inventory.call(&"server_give", 2, GlowstickRules.ITEM)
	glowsticks.call(&"server_crack", 2)
	glowsticks.call(&"server_drop", 2)
	partner.global_position += Vector3(0.0, 0.0, -200.0)


func _spawn(peer: int, at: Vector3, local: bool) -> PlayerController:
	var p: PlayerController = (load(PLAYER) as PackedScene).instantiate()
	p.name = "Player%d" % peer
	p.set_meta(&"peer_id", peer)
	p.add_to_group(&"players")
	add_child(p)
	p.global_position = at
	EventBus.publish(&"player.spawned", {"player": p, "local": local})
	var animator := PlayerBodyAnimator.new()
	animator.player = p
	p.add_child(animator)
	return p


func _physics_process(_delta: float) -> void:
	if _player == null:
		return
	_ticks += 1
	# A slow sweep: left and right, and down toward the feet and back up.
	var t := float(_ticks) / 60.0
	_player.intent().remote_look = true
	_player.intent().look_yaw = sin(t * 0.9) * 0.6
	_player.intent().look_pitch = -0.15 - 0.7 * (0.5 - 0.5 * cos(t * 1.3))
