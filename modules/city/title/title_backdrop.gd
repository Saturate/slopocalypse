extends Node3D
## Behind the title screen: the city at golden hour, the camera drifting slowly down one of
## its avenues and back. Built only when the title asks (boot adds it while the menu shows),
## with just the world, the city, its lamps and the daylight: no players, soldiers or net.
## `shown` fires once the street is loaded, so the title can fade from its plain backdrop.

signal shown

const WORLD := "res://modules/world/scenes/world.tscn"
const CITY := "res://modules/city/city_module.gd"
const LIGHTS := "res://modules/lights/lights_module.gd"
const DAYTIME := "res://modules/daytime/daytime_module.gd"
## Afternoon: long shadows and warm light, before the evening haze thickens.
const HOUR := 15.5
## Seconds for one way down the avenue.
const DRIFT_SECONDS := 70.0
const EYE_HEIGHT := 2.4
## Metres kept clear of each end of the avenue.
const END_MARGIN := 18.0

var _camera := Camera3D.new()
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _site: Node3D
var _time := 0.0


func _ready() -> void:
	set_process(false)
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	if not is_inside_tree():
		return
	var terrain := world.get_node("Terrain") as VoxelWorld
	for path: String in [LIGHTS, DAYTIME]:
		if ResourceLoader.exists(path):
			add_child((load(path) as GDScript).new())
	var city: Node = (load(CITY) as GDScript).new()
	add_child(city)
	city.call(&"_on_world_ready", {})
	EventBus.publish(&"world.ready", {})
	EventBus.publish(&"admin.set_hour", {"hour": HOUR})
	_site = city.get(&"site")
	if _site == null:
		return
	var street: Rect2 = (_site.get(&"plan")["streets"] as Array)[2]
	_from = Vector3(street.get_center().x, EYE_HEIGHT, street.position.y + END_MARGIN)
	_to = Vector3(street.get_center().x, EYE_HEIGHT, street.end.y - END_MARGIN)
	_camera.fov = 70.0
	_camera.far = 800.0
	add_child(_camera)
	_camera.current = true
	_camera.add_child(terrain.make_viewer())
	(world.get_node("Scenery") as SceneryScatter).update_around([_site.global_position], INF)
	terrain.update_around([_site.global_position], INF)
	_place(0.0)
	set_process(true)
	# Deferred: if the ground was ready at once, this all ran inside add_child, before the
	# caller could connect.
	shown.emit.call_deferred()


func _process(delta: float) -> void:
	_time += delta
	_place(_time)


## Ping-pong down the avenue, eased at the ends, looking a little ahead and to the side.
func _place(t: float) -> void:
	var phase := fmod(t / DRIFT_SECONDS, 2.0)
	var along := phase if phase <= 1.0 else 2.0 - phase
	along = smoothstep(0.0, 1.0, along)
	var forward := 1.0 if phase <= 1.0 else -1.0
	var local := _from.lerp(_to, along)
	var ahead := local + Vector3(sin(t * 0.07) * 6.0, -0.6, 30.0 * forward)
	_camera.global_position = _site.global_transform * local
	_camera.look_at(_site.global_transform * ahead)
