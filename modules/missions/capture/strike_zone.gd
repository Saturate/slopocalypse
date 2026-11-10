extends Node3D
## Capture setup: out on a mission. First person at the strike zone, the clock running, the
## "DRIVE" marker over the objective crate and the mission lines in the top left.

const WORLD := "res://modules/world/scenes/world.tscn"
const PLAYER := "res://modules/player/scenes/player.tscn"
const MISSIONS := "res://modules/missions/missions_module.gd"
const INVENTORY := "res://modules/inventory/inventory_module.gd"

var _player: PlayerController
var _missions: Node
var _ticks := 0


func _ready() -> void:
	await VoxelWorld.add_and_wait(self, WORLD)
	add_child((load(INVENTORY) as GDScript).new())
	_missions = (load(MISSIONS) as GDScript).new()
	add_child(_missions)
	EventBus.subscribe(&"player.move_requested", func(p: Dictionary) -> void: (p["player"] as Node3D).global_position = p["position"])
	var spawn := (get_tree().get_first_node_in_group(&"spawn_point") as Node3D).global_position
	_player = (load(PLAYER) as PackedScene).instantiate()
	_player.set_meta(&"peer_id", 1)
	_player.add_to_group(&"players")
	add_child(_player)
	_player.global_position = spawn
	EventBus.publish(&"player.spawned", {"player": _player, "local": true})
	PlayerBody.first_person(_player.get_node("Body"))
	(_player.get_node("Head/Camera") as Camera3D).current = true
	EventBus.publish(&"world.ready", {"spawn": spawn})
	_missions.call(&"server_choose", 1, 0)
	_missions.call(&"server_ride_out")
	_missions.call(&"server_set_tokens", 1, 250)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(_delta: float) -> void:
	if _player == null:
		return
	_ticks += 1
	if _ticks == 20:
		# Into the zone, 25 m short of the crate, facing it.
		var crate: Vector3 = _missions.get(&"objective_at")
		var zone: Vector3 = _missions.get(&"zone")
		var at := crate + (zone - crate).normalized() * 4.0 + Vector3(0, 0, 25)
		var ground := get_tree().get_first_node_in_group(&"ground")
		at.y = float(ground.call(&"ground_height", at.x, at.z)) + 0.2
		_player.global_position = at
		_player.look_at(Vector3(crate.x, at.y, crate.z), Vector3.UP)
