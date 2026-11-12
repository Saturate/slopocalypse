extends Node3D
## Capture setup: the test range. The row of buildings seen from the road, then a burst of
## blasts on each one's front wall, so each material's breakage can be compared side by side.

const WORLD := "res://modules/world/scenes/world.tscn"
const PLAYER := "res://modules/player/scenes/player.tscn"
const MODULES: Array[String] = [
	"res://modules/weapons/weapons_module.gd",
	"res://modules/inventory/inventory_module.gd",
	"res://modules/missions/missions_module.gd",
	"res://modules/range/range_module.gd",
]
const BLAST_AT := 60
const BLAST_EVERY := 25

var _player: PlayerController
var _missions: Node
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


func _physics_process(_delta: float) -> void:
	if _player == null or _missions == null:
		return
	var buildings: Array = _missions.call(&"building_nodes")
	if buildings.is_empty():
		return
	_ticks += 1
	if _ticks == 5:
		_player.set_physics_process(false)
		# From across the road, high enough to see every building's front.
		var first := buildings[0] as Node3D
		var last := buildings[buildings.size() - 1] as Node3D
		var mid := first.global_position.lerp(last.global_position, 0.5)
		var cam := Camera3D.new()
		add_child(cam)
		# The row stands on the +x side of the road; look from the far side of the road.
		cam.global_position = mid + Vector3(-12.0, 6.0, 0.0)
		cam.look_at(mid + Vector3.UP * 1.0, Vector3.UP)
		cam.current = true
	var i := (_ticks - BLAST_AT) / BLAST_EVERY
	if _ticks >= BLAST_AT and (_ticks - BLAST_AT) % BLAST_EVERY == 0 and i < buildings.size():
		var b := buildings[i] as Node3D
		var front := b.global_transform * Vector3(0.0, 1.0, -float(b.get(&"spec")["depth"]) / 2.0 - 0.3)
		Net.server_broadcast(&"explosion", {"position": front, "radius": 2.5})
