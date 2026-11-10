extends Node3D
## Capture setup: first person in the home tunnel, turning from the mission board on the wall
## to the transport car parked further in, then the board screen open.

const WORLD := "res://modules/world/scenes/world.tscn"
const PLAYER := "res://modules/player/scenes/player.tscn"
const MISSIONS := "res://modules/missions/missions_module.gd"
const OPEN_AT := 100

var _player: PlayerController
var _missions: Node
var _ticks := 0


func _ready() -> void:
	await VoxelWorld.add_and_wait(self, WORLD)
	_missions = (load(MISSIONS) as GDScript).new()
	add_child(_missions)
	var spawn := (get_tree().get_first_node_in_group(&"spawn_point") as Node3D).global_position
	_player = (load(PLAYER) as PackedScene).instantiate()
	_player.set_meta(&"peer_id", 1)
	_player.add_to_group(&"players")
	add_child(_player)
	_player.global_position = spawn + Vector3(-1.0, -0.5, 0.0)
	EventBus.publish(&"player.spawned", {"player": _player, "local": true})
	PlayerBody.first_person(_player.get_node("Body"))
	(_player.get_node("Head/Camera") as Camera3D).current = true
	EventBus.publish(&"world.ready", {"spawn": spawn})
	_missions.call(&"server_choose", 1, 0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(_delta: float) -> void:
	if _player == null:
		return
	_ticks += 1
	# Face the board, then the parked car, then open the board screen.
	if _ticks == 2:
		_face(_missions.get_node("MissionBoard") as Node3D)
	elif _ticks == 45:
		_face(_missions.get_node("Transport") as Node3D)
	elif _ticks == OPEN_AT:
		EventBus.publish(&"missions.board_opened", {"peer": 1})


func _face(target: Node3D) -> void:
	var at := target.global_position
	_player.look_at(Vector3(at.x, _player.global_position.y, at.z), Vector3.UP)
