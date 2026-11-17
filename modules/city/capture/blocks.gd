extends Node3D
## Capture setup: the hand-made city blocks side by side on flat ground, seen from above at
## an angle, then each from closer at eye height.

const WORLD := "res://modules/world/scenes/flat_world.tscn"
const SPACING := 40.0

var _camera := Camera3D.new()
var _ticks := 0
var _nodes: Array[CityBlockNode] = []


func _ready() -> void:
	var world: Node3D = (load(WORLD) as PackedScene).instantiate()
	add_child(world)
	var names := CityBlock.names()
	for i in names.size():
		var n := CityBlockNode.new()
		n.block = CityBlock.load_named(names[i])
		n.variation_seed = i + 1
		n.position = Vector3((i - (names.size() - 1) / 2.0) * SPACING, 0.0, 0.0)
		add_child(n)
		n.build_all()
		_nodes.append(n)
	_camera.fov = 70.0
	_camera.far = 600.0
	add_child(_camera)
	_camera.current = true
	_camera.global_position = Vector3(0.0, 55.0, 70.0)
	_camera.look_at(Vector3.ZERO)


func _process(_delta: float) -> void:
	_ticks += 1
	var k := _ticks / 90
	if _ticks % 90 == 0 and k - 1 < _nodes.size():
		var n := _nodes[k - 1]
		_camera.global_position = n.global_position + Vector3(14.0, 1.7, 24.0)
		_camera.look_at(n.global_position + Vector3(0.0, 3.0, 0.0))
