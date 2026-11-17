extends Node3D
## Capture setup: one soldier of each faction in a row on flat ground, then two squads of
## hostile factions facing each other across 25 m.

const WORLD := "res://modules/world/scenes/flat_world.tscn"
const MODULES := ["res://modules/factions/factions_module.gd", "res://modules/weapons/weapons_module.gd", "res://modules/inventory/inventory_module.gd"]
const ENEMIES := "res://modules/enemies/enemies_module.gd"

var _camera := Camera3D.new()
var _ticks := 0
var _enemies: Node


func _ready() -> void:
	add_child((load(WORLD) as PackedScene).instantiate())
	for path: String in MODULES:
		add_child((load(path) as GDScript).new())
	_enemies = (load(ENEMIES) as GDScript).new()
	add_child(_enemies)
	var ids := ["militia", "regulars", "scavengers"]
	for i in ids.size():
		var s: Node3D = _enemies.call(&"server_spawn_guard", Vector3(-2.5 + i * 2.5, 0, 0), PI, [], ids[i])
		# Lined up for the photo: brains off until the fight.
		s.set_meta(&"capture_still", true)
	_camera.fov = 50.0
	add_child(_camera)
	_camera.current = true
	_camera.global_position = Vector3(0, 1.6, 6.5)
	_camera.look_at(Vector3(0, 1.1, 0))
	for n: Node in get_tree().get_nodes_in_group(&"enemies"):
		var brain := n.get_node_or_null(^"Brain")
		if brain != null:
			brain.set_physics_process(false)


func _process(_delta: float) -> void:
	_ticks += 1
	if _ticks == 120:
		for n: Node in get_tree().get_nodes_in_group(&"enemies"):
			n.queue_free()
		for i in 3:
			_enemies.call(&"server_spawn_guard", Vector3(-4.0 + i * 4.0, 0, 0), 0.0, [], "militia")
			_enemies.call(&"server_spawn_guard", Vector3(-4.0 + i * 4.0, 0, -25), PI, [], "regulars")
		_camera.global_position = Vector3(18, 7, -12.5)
		_camera.look_at(Vector3(0, 1, -12.5))
