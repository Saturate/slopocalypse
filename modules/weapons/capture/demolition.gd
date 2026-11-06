extends Node3D
## Capture setup: from a raised viewpoint, demolition charges blow craters into the voxel
## terrain next to a training dummy, with flash, dust and debris.

const WORLD := "res://modules/world/scenes/world.tscn"
const DUMMY := "res://modules/training/scenes/dummy.tscn"

var _voxels: VoxelWorld
var _camera := Camera3D.new()
var _ticks := 0
var _charges: Array[Vector3] = [Vector3(0, 0, -10), Vector3(4, 0, -14), Vector3(-3, 0, -18)]


func _ready() -> void:
	var world := (load(WORLD) as PackedScene).instantiate()
	add_child(world)
	_voxels = world.get_node("Terrain")
	var effects := ExplosionEffects.new()
	add_child(effects)
	var dummy: Node3D = (load(DUMMY) as PackedScene).instantiate()
	add_child(dummy)
	dummy.global_position = Vector3(2, 0, -11)
	EventBus.subscribe(&"explosion", func(p: Dictionary) -> void: _voxels.server_dig(p["position"], float(p["radius"])))
	add_child(_camera)
	_camera.current = true
	_camera.fov = 65.0
	_camera.global_transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-28.0), 0.0, 0.0)), Vector3(0, 9, 4))


func _physics_process(_delta: float) -> void:
	_ticks += 1
	# Spaced so each blast is caught mid-cloud by a sampled frame.
	for i in _charges.size():
		if _ticks == 40 + i * 60:
			var charge := DemolitionCharge.new()
			charge.stats = {"fuse_seconds": 0.05, "radius": 3.0, "damage": 150.0}
			add_child(charge)
			charge.global_position = _charges[i]
