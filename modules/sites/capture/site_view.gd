extends Node3D
## Capture base: one map site and its buildings seen from the track leading to it, walking
## in toward it over the frames. Each capture names the kind, how far out it starts and
## where to look; `SITE_INDEX` picks another site of that kind (the first when unset).

const WORLD := "res://modules/world/scenes/world.tscn"
const MODULE := "res://modules/sites/sites_module.gd"
## The eye over the ground, metres.
const EYE := 1.8

var kind := "farm"
## Metres out along the track from the site's centre, at the start and the end.
var from_distance := 40.0
var to_distance := 25.0
## Where on the site to look, metres over the pad.
var look_up := 3.0
## How far round from straight down the track the camera stands (radians), so a door
## facing the track is not seen square on.
var swing := 0.15
## The sun comes from behind the camera, this far round to one side (radians) and this high
## (radians over the horizon), so the side facing the camera is lit and shows its detail.
const SUN_SIDE := 0.6
const SUN_HIGH := 0.75

var _camera := Camera3D.new()
var _terrain: VoxelWorld
var _site: Dictionary = {}
var _t := 0.0


func _ready() -> void:
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	_terrain = world.get_node("Terrain")
	var sites: Node = (load(MODULE) as GDScript).new()
	add_child(sites)
	EventBus.publish(&"world.ready", {"spawn": VoxelWorld.spawn_of(world)})
	# Every frame of the sheet shows the buildings, not the first few going up.
	sites.call(&"build_all")
	var wanted := int(OS.get_environment("SITE_INDEX")) if OS.has_environment("SITE_INDEX") else 0
	var seen := 0
	for s: Dictionary in _terrain.map_site_list():
		if s["kind"] == kind:
			if seen == wanted:
				_site = s
				break
			seen += 1
	if _site.is_empty():
		push_error("no %s site %d on this map" % [kind, wanted])
		return
	var centre: Vector3 = _site["centre"]
	_camera.fov = 70.0
	_camera.far = 900.0
	add_child(_camera)
	_camera.current = true
	_camera.add_child(_terrain.make_viewer())
	_place(0.0)
	_light_from_behind(world.get_node("Sun") as DirectionalLight3D, centre)
	_terrain.update_around([centre, _camera.global_position], INF)
	(world.get_node("Scenery") as SceneryScatter).update_around([centre, _camera.global_position], INF)


func _process(delta: float) -> void:
	if _site.is_empty():
		return
	_t += delta
	_place(clampf(_t / 2.0, 0.0, 1.0))


func _place(share: float) -> void:
	var centre: Vector3 = _site["centre"]
	var toward: Vector3 = (_site["toward"] as Vector3).rotated(Vector3.UP, swing)
	var at := centre + toward * lerpf(from_distance, to_distance, share)
	at.y = _terrain.surface_height(at.x, at.z) + EYE
	_camera.global_position = at
	_camera.look_at(centre + Vector3.UP * look_up)


func _light_from_behind(sun: DirectionalLight3D, centre: Vector3) -> void:
	var ahead := centre - _camera.global_position
	ahead.y = 0.0
	var flat := ahead.normalized().rotated(Vector3.UP, SUN_SIDE)
	var shine := (flat * cos(SUN_HIGH) + Vector3.DOWN * sin(SUN_HIGH)).normalized()
	sun.global_basis = Basis.looking_at(shine, Vector3.UP)
