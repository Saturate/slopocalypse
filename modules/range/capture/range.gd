extends Node3D
## Capture setup: the test range, one building at a time from close in front: a spread of
## rifle rounds into its front wall (holes in wood, chips off brick and concrete, marks on
## glass), held for a moment, then on to the next. `--frames 320 --sheet 6` gives about one
## panel per building, after its rounds.

const WORLD := "res://modules/world/scenes/world.tscn"
const PLAYER := "res://modules/player/scenes/player.tscn"
const MODULES: Array[String] = [
	"res://modules/weapons/weapons_module.gd",
	"res://modules/inventory/inventory_module.gd",
	"res://modules/missions/missions_module.gd",
	"res://modules/range/range_module.gd",
]
## Ticks spent on each building, and how many of them fire.
const DWELL := 60
const FIRING := 36
const START := 10

var _player: PlayerController
var _missions: Node
var _cam: Camera3D
var _ticks := 0


func _ready() -> void:
	Net.extra_args = PackedStringArray(["--range"])
	await VoxelWorld.add_and_wait(self, WORLD)
	for path in MODULES:
		add_child((load(path) as GDScript).new())
	_missions = get_tree().get_first_node_in_group(&"missions_api")
	EventBus.subscribe(&"player.move_requested", func(p: Dictionary) -> void: (p["player"] as Node3D).global_position = p["position"])
	var spawn := (get_tree().get_first_node_in_group(&"spawn_point") as Node3D).global_position
	_player = (load(PLAYER) as PackedScene).instantiate()
	_player.set_meta(&"peer_id", 1)
	_player.add_to_group(&"players")
	add_child(_player)
	_player.global_position = spawn
	EventBus.publish(&"world.ready", {"spawn": spawn})
	EventBus.publish(&"player.spawned", {"player": _player, "local": true})
	_cam = Camera3D.new()
	add_child(_cam)


func _physics_process(_delta: float) -> void:
	if _player == null or _missions == null:
		return
	var buildings: Array = _missions.call(&"building_nodes")
	if buildings.is_empty():
		return
	_ticks += 1
	if _ticks < START:
		return
	_player.set_physics_process(false)
	var t := _ticks - START
	var i := t / DWELL
	if i >= buildings.size():
		return
	var b := buildings[i] as Node3D
	var spec: Dictionary = b.get(&"spec")
	var d := float(spec["depth"])
	if t % DWELL == 0:
		# Square on to its front, a few metres out, a little above head height.
		_cam.global_position = b.global_transform * Vector3(0.6, 1.9, -d / 2.0 - 6.5)
		_cam.look_at(b.global_transform * Vector3(0.0, 1.3, -d / 2.0), Vector3.UP)
		_cam.current = true
	if t % DWELL < FIRING:
		_shoot(b, t % DWELL)


## One rifle round into the building's front wall, spread across it and up it over the
## ticks, sent the way a real shot arrives (the event every instance replays).
func _shoot(b: Node3D, k: int) -> void:
	var spec: Dictionary = b.get(&"spec")
	var w := float(spec["width"])
	var d := float(spec["depth"])
	var local := Vector3(lerpf(-w / 2.0 + 0.3, w / 2.0 - 0.3, fmod(k * 0.37, 1.0)), 0.4 + fmod(k * 0.23, 1.0) * 2.0, -d / 2.0)
	var to := b.global_transform * local
	var from := to + b.global_transform.basis * Vector3(0.0, 0.3, -12.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to + (to - from).normalized() * 0.5))
	if hit.is_empty():
		return
	EventBus.publish(&"weapon.fired", {"holder": null, "from": from, "to": hit["position"], "collider": hit["collider"], "damage": 25.0})
