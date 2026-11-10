extends Node3D
## Capture setup: first person over a dead soldier's body with the search prompt, then the
## loot screen open on it (backpack left, body right) with one of the body's items
## mid-drag over the backpack.

const WORLD := "res://modules/world/scenes/world.tscn"
const PLAYER := "res://modules/player/scenes/player.tscn"
const INVENTORY := "res://modules/inventory/inventory_module.gd"
const WEAPONS := "res://modules/weapons/weapons_module.gd"
const OPEN_AT := 60

var _player: PlayerController
var _inventory: Node
var _body: LootBody
var _ticks := 0


func _ready() -> void:
	await VoxelWorld.add_and_wait(self, WORLD)
	add_child((load(WEAPONS) as GDScript).new())
	_inventory = (load(INVENTORY) as GDScript).new()
	add_child(_inventory)
	_player = _spawn(1, Vector3(3.0, 0.1, -2.6), true)
	var animator := PlayerBodyAnimator.new()
	animator.name = "BodyAnimator"
	animator.player = _player
	_player.add_child(animator)
	PlayerBody.first_person(_player.get_node("Body"))
	(_player.get_node("Head/Camera") as Camera3D).current = true
	var victim := _spawn(-7, _player.global_position + Vector3(-0.7, 0.0, -2.1), false)
	victim.add_to_group(&"enemies")
	EventBus.publish(&"enemy.died", {"enemy": victim, "position": victim.global_position})
	victim.visible = false
	_body = get_tree().get_nodes_in_group(&"loot_bodies")[-1]
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _spawn(peer: int, at: Vector3, local: bool) -> PlayerController:
	var player: PlayerController = (load(PLAYER) as PackedScene).instantiate()
	player.set_meta(&"peer_id", peer)
	player.add_to_group(&"players")
	add_child(player)
	player.global_position = at
	EventBus.publish(&"player.spawned", {"player": player, "local": local, "npc": not local})
	return player


func _physics_process(_delta: float) -> void:
	if _player == null or _body == null:
		return
	_ticks += 1
	if _ticks < 30:
		# Look down at the body.
		_player.intent().look_delta.y += 0.02
		_player.intent().look_delta.x += 0.008
	elif _ticks == OPEN_AT:
		_inventory.call(&"server_open", 1, _body)
		var screen := _inventory.get_node("LootScreen") as LootScreen
		var item: Dictionary = (_inventory.call(&"loot_grid") as InventoryGrid).items()[0]
		screen.pick(true, Vector2i(int(item["x"]), int(item["y"])))
		Input.warp_mouse(get_viewport().get_visible_rect().size * Vector2(0.3, 0.45))
