extends Node3D
## Capture setup: the admin panel open over the world, with two other players listed.

const WORLD := "res://modules/world/scenes/world.tscn"

var _camera := Camera3D.new()


func _ready() -> void:
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	var spawn := (world.get_node("SpawnPoint") as Marker3D).global_position
	add_child(_camera)
	_camera.current = true
	_camera.global_position = spawn + Vector3(0, 0.7, 0)
	_camera.look_at(spawn + Vector3(0, 0.7, -30))
	var admin: Node = (load("res://modules/admin/admin_module.gd") as GDScript).new()
	add_child(admin)
	admin.set(&"is_admin_here", true)
	admin.emit_signal(&"players_changed", {7: "Kim", 9: "Saturate"})
	(admin.get_node("Panel") as Object).call(&"open")
