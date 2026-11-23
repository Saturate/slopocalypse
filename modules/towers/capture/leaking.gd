extends Node3D
## Capture setup: a water tower beside the road, shot five times in the tank from where the
## camera stands; streams pour from the holes and a puddle spreads under it.

const WORLD := "res://modules/world/scenes/world.tscn"
const TOWERS := "res://modules/towers/towers_module.gd"
## Frame -> [height up the tank (m), angle round it from the camera's side (radians)].
const SHOTS := {20: [0.4, 0.0], 45: [1.1, 0.35], 70: [0.7, -0.4], 95: [1.6, 0.15], 120: [2.5, -0.2]}

var _camera := Camera3D.new()
var _ticks := 0
var _towers: Node
var _tower: WaterTower


func _ready() -> void:
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	var terrain := world.get_node("Terrain") as VoxelWorld
	_towers = (load(TOWERS) as GDScript).new()
	add_child(_towers)
	var at := terrain.road_point(60.0) + Vector3(14.0, 0.0, 0.0)
	at.y = terrain.ground_height(at.x, at.z)
	_towers.call(&"place", [Transform3D(Basis.IDENTITY, at)] as Array[Transform3D])
	_tower = (_towers.get(&"towers") as Array)[0]
	var from := at + Vector3(-13.0, 4.0, 9.0)
	_camera.fov = 70.0
	_camera.far = 600.0
	add_child(_camera)
	_camera.current = true
	_camera.global_position = from
	_camera.look_at(at + Vector3.UP * 4.5)
	_camera.add_child(terrain.make_viewer())
	(world.get_node("Scenery") as SceneryScatter).update_around([at], INF)
	terrain.update_around([at], INF)


func _process(_delta: float) -> void:
	if _tower == null:
		return
	_ticks += 1
	if SHOTS.has(_ticks):
		var s: Array = SHOTS[_ticks]
		var toward := (_camera.global_position - _tower.global_position)
		toward.y = 0.0
		var dir := toward.normalized().rotated(Vector3.UP, float(s[1]))
		var r := float(_tower.config["radius"])
		var point := _tower.global_position + dir * r + Vector3.UP * (float(_tower.config["height"]) + float(s[0]))
		EventBus.publish(&"weapon.fired", {"from": _camera.global_position, "to": point, "collider": _tower})
