extends Node3D
## Capture setup (--frames 120 --sheet 2): civilians strolling by their doors on a city
## street, then the same street a few seconds after shots ring out down the road.

const WORLD := "res://modules/world/scenes/world.tscn"
const CITY := "res://modules/city/city_module.gd"
const MODULES := ["res://modules/weapons/weapons_module.gd", "res://modules/inventory/inventory_module.gd", "res://modules/enemies/enemies_module.gd"]

var _camera := Camera3D.new()
var _city: Node
var _site: CitySite
var _ticks := 0


func _ready() -> void:
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	var terrain := world.get_node("Terrain") as VoxelWorld
	for path: String in MODULES:
		add_child((load(path) as GDScript).new())
	_city = (load(CITY) as GDScript).new()
	add_child(_city)
	_city.call(&"_on_world_ready", {})
	_site = _city.get(&"site")
	_camera.fov = 70.0
	_camera.far = 600.0
	add_child(_camera)
	_camera.current = true
	_camera.add_child(terrain.make_viewer())
	(world.get_node("Scenery") as SceneryScatter).update_around([_site.global_position], INF)
	terrain.update_around([_site.global_position], INF)


func _physics_process(_delta: float) -> void:
	if _site == null or _site.pending() > 0:
		return
	_ticks += 1
	var b: Dictionary = (_site.plan["buildings"] as Array)[3]
	var people := _city.get(&"civilians") as CityCivilians
	var door := people.door_of(b)
	if _ticks == 2:
		people.config["per_building"] = [3, 3]
		people.server_update([door])
	if _ticks < 120:
		var f: Vector2 = b["facing"]
		var out := (_site.global_basis * Vector3(f.x, 0.0, f.y)).normalized()
		_camera.global_position = door + out * 12.0 + Vector3.UP * 3.0
		_camera.look_at(door + Vector3.UP * 1.0)
	if _ticks == 140:
		var f2: Vector2 = b["facing"]
		var from := door + (_site.global_basis * Vector3(f2.x, 0.0, f2.y)).normalized() * 30.0
		EventBus.publish(&"weapon.fired", {"from": from, "to": door, "damage": 0.0})
