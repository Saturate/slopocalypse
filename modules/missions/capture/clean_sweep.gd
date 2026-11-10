extends Node3D
## Capture setup: out on a Clean Sweep. First person looking at a building with its sentry
## at the door, the guard count in the top left; then the mission board with its codenames.

const WORLD := "res://modules/world/scenes/world.tscn"
const PLAYER := "res://modules/player/scenes/player.tscn"
const MISSIONS := "res://modules/missions/missions_module.gd"
const INVENTORY := "res://modules/inventory/inventory_module.gd"
const ENEMIES := "res://modules/enemies/enemies_module.gd"
const WEAPONS := "res://modules/weapons/weapons_module.gd"
const BOARD_AT := 110

var _player: PlayerController
var _missions: Node
var _ticks := 0


func _ready() -> void:
	await VoxelWorld.add_and_wait(self, WORLD)
	add_child((load(WEAPONS) as GDScript).new())
	add_child((load(INVENTORY) as GDScript).new())
	add_child((load(ENEMIES) as GDScript).new())
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
	var cfg: Dictionary = _missions.get(&"config")
	for seed_value in 50:
		var offers: Array = (load(MISSIONS) as GDScript).call(&"roll_offers", cfg, seed_value)
		var sweeps := offers.filter(func(o: Dictionary) -> bool: return o["type"] == "clean_sweep")
		if not sweeps.is_empty():
			_missions.set(&"offers", offers)
			_missions.call(&"server_choose", 1, offers.find(sweeps[0]))
			break
	_missions.call(&"server_ride_out")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(_delta: float) -> void:
	if _player == null:
		return
	_ticks += 1
	if _ticks == 10:
		# 18 m in front of the first building's door, facing it, out of the guards' sight for
		# a moment.
		var b := (_missions.call(&"building_nodes") as Array)[0] as MissionBuilding
		var d := float(b.spec["depth"])
		var at := b.global_transform * Vector3(0, 0, -d / 2.0 - 18.0)
		at.y = float(_missions.call(&"ground_y", at.x, at.z)) + 0.2
		_player.global_position = at
		_player.set_physics_process(false)
		# The player's own camera follows its look intent; a fixed one frames the building.
		var cam := Camera3D.new()
		add_child(cam)
		# From high over the road, looking down on the building and its guards.
		cam.global_position = b.global_position + (at - b.global_position).normalized() * 16.0 + Vector3.UP * 12.0
		cam.look_at(b.global_position + Vector3.UP * 1.2, Vector3.UP)
		cam.current = true
	elif _ticks == BOARD_AT:
		EventBus.publish(&"missions.board_opened", {"peer": 1})
