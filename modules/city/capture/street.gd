extends Node3D
## Capture setup: the first city blocks from the road, then from inside a flat looking out of
## its window, then from the flat roof.

const WORLD := "res://modules/world/scenes/world.tscn"
const CITY := "res://modules/city/city_module.gd"

var _camera := Camera3D.new()
var _ticks := 0
var _city: Node
var _terrain: VoxelWorld


func _ready() -> void:
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	_terrain = world.get_node("Terrain") as VoxelWorld
	_city = (load(CITY) as GDScript).new()
	add_child(_city)
	_city.call(&"_on_world_ready", {})
	var from := _terrain.road_point(128.0) + Vector3.UP * 2.0
	_camera.fov = 75.0
	_camera.far = 600.0
	add_child(_camera)
	_camera.current = true
	_camera.global_position = from
	_camera.look_at(_terrain.road_point(170.0) + Vector3.UP * 6.0)
	_camera.add_child(_terrain.make_viewer())
	(world.get_node("Scenery") as SceneryScatter).update_around([from], INF)
	_terrain.update_around([from], INF)


func _process(_delta: float) -> void:
	if _city == null:
		return
	_ticks += 1
	var first := (_city.get(&"buildings") as Array)[0] as CityBuilding
	if first == null:
		return
	var plan := first.plan()
	if _ticks == 120:
		# Inside the first flat on the second floor, looking out at the road.
		var flat: Vector2 = (plan["flats"] as Array)[0]
		var inner := VoxApartment.inner_rect(plan, flat)
		var level := float((plan["levels"] as Array)[1])
		# Just inside the street-side wall, between its windows and the rooms behind.
		var x := VoxApartment.window_x(flat, 2, 0)
		var inside := first.global_transform * Vector3(x + 0.6, level + 1.6, inner.position.y + 1.4)
		var out := first.global_transform * Vector3(x - 1.0, level + 1.0, -20.0)
		_camera.global_position = inside
		_camera.look_at(out)
	if _ticks == 240:
		var roof := float(plan["eaves"]) + 2.0
		_camera.global_position = first.global_transform * Vector3(0.0, roof + 6.0, 12.0)
		_camera.look_at(first.global_transform * Vector3(0.0, roof - 4.0, -25.0))
