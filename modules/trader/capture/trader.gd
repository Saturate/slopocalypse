extends Node3D
## Capture setup: first person at the trader's stall in the home tunnel, then the trade
## screen open with some tokens.

const WORLD := "res://modules/world/scenes/world.tscn"
const PLAYER := "res://modules/player/scenes/player.tscn"
const INVENTORY := "res://modules/inventory/inventory_module.gd"
const MISSIONS := "res://modules/missions/missions_module.gd"
const TRADER := "res://modules/trader/trader_module.gd"
const OPEN_AT := 60

var _player: PlayerController
var _trader: Node
var _ticks := 0


func _ready() -> void:
	await VoxelWorld.add_and_wait(self, WORLD)
	add_child((load(INVENTORY) as GDScript).new())
	var missions: Node = (load(MISSIONS) as GDScript).new()
	add_child(missions)
	_trader = (load(TRADER) as GDScript).new()
	add_child(_trader)
	var spawn := (get_tree().get_first_node_in_group(&"spawn_point") as Node3D).global_position
	_player = (load(PLAYER) as PackedScene).instantiate()
	_player.set_meta(&"peer_id", 1)
	_player.add_to_group(&"players")
	add_child(_player)
	_player.global_position = spawn
	EventBus.publish(&"player.spawned", {"player": _player, "local": true})
	PlayerBody.first_person(_player.get_node("Body"))
	EventBus.publish(&"world.ready", {"spawn": spawn})
	missions.call(&"server_set_tokens", 1, 340)
	var stall := _trader.get_node("TraderStall") as Node3D
	_player.global_position = stall.global_position + Vector3(-2.6, 0.2, -0.5)
	_player.set_physics_process(false)
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = _player.global_position + Vector3.UP * 1.6
	cam.look_at(stall.global_position + Vector3.UP * 1.3, Vector3.UP)
	cam.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(_delta: float) -> void:
	_ticks += 1
	if _ticks == OPEN_AT:
		EventBus.publish(&"trader.opened", {"peer": 1})
