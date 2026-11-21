extends Node3D
## Capture base: a mission run at one of the map's sites. The board's template named by
## `place` is sent to the first site of `kind`; the group rides out, then the camera looks
## from the drop-off toward the site for the first half of the frames and from high over the
## zone for the rest.

const WORLD := "res://modules/world/scenes/world.tscn"
const PLAYER := "res://modules/player/scenes/player.tscn"
const MISSIONS := "res://modules/missions/missions_module.gd"
const INVENTORY := "res://modules/inventory/inventory_module.gd"
const ENEMIES := "res://modules/enemies/enemies_module.gd"
const WEAPONS := "res://modules/weapons/weapons_module.gd"
const SITES := "res://modules/sites/sites_module.gd"
## The eye over the ground at the drop-off, metres.
const EYE := 1.8
## Seconds from the drop-off before the camera goes up over the zone.
const GROUND_SECONDS := 2.0
## The sun this far round from behind the camera (radians) and this high over the horizon.
const SUN_SIDE := 0.6
const SUN_HIGH := 0.75

var kind := "farm"
var place := "Farm lodge"
## How high over the zone the second view is, and how far back toward the drop-off.
var above := 70.0
var back := 35.0

var _camera := Camera3D.new()
var _terrain: VoxelWorld
var _scenery: SceneryScatter
var _missions: Node
var _ready_to_film := false
var _t := 0.0


func _ready() -> void:
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	_terrain = world.get_node("Terrain")
	_scenery = world.get_node("Scenery")
	add_child((load(WEAPONS) as GDScript).new())
	add_child((load(INVENTORY) as GDScript).new())
	add_child((load(ENEMIES) as GDScript).new())
	var sites: Node = (load(SITES) as GDScript).new()
	add_child(sites)
	_missions = (load(MISSIONS) as GDScript).new()
	add_child(_missions)
	EventBus.subscribe(&"player.move_requested", func(p: Dictionary) -> void: (p["player"] as Node3D).global_position = p["position"])
	var spawn := (get_tree().get_first_node_in_group(&"spawn_point") as Node3D).global_position
	var player: PlayerController = (load(PLAYER) as PackedScene).instantiate()
	player.set_meta(&"peer_id", 1)
	player.add_to_group(&"players")
	add_child(player)
	player.global_position = spawn
	player.set_physics_process(false)
	EventBus.publish(&"world.ready", {"spawn": spawn})
	sites.call(&"build_all")
	var all: Array = _missions.get(&"sites")
	var first := all.filter(func(s: Dictionary) -> bool: return s["kind"] == kind)
	if first.is_empty():
		push_error("no %s site on this map" % kind)
		return
	var cfg: Dictionary = (_missions.get(&"config") as Dictionary).duplicate(true)
	var template: Dictionary = (cfg["missions"] as Array).filter(func(t: Dictionary) -> bool: return t["place"] == place)[0]
	# Whatever its distance: the capture wants this site.
	template["distance"] = [0.0, 100000.0]
	cfg["missions"] = [template]
	cfg["offered"] = 1.0
	var offers: Array = (load(MISSIONS) as GDScript).call(&"roll_offers", cfg, 1, [first[0]], spawn)
	_missions.set(&"offers", offers)
	_missions.call(&"server_choose", 1, 0)
	_missions.call(&"server_ride_out")
	_camera.fov = 70.0
	_camera.far = 900.0
	add_child(_camera)
	_camera.current = true
	_camera.add_child(_terrain.make_viewer())
	var zone: Vector3 = _missions.get(&"zone")
	var drop: Vector3 = _missions.call(&"dropoff_of", _missions.get(&"current"))
	_terrain.update_around([zone, drop], INF)
	_scenery.update_around([zone, drop] as Array[Vector3], INF)
	_ready_to_film = true
	_place()
	_light_from_behind(world.get_node("Sun") as DirectionalLight3D)


func _process(delta: float) -> void:
	if not _ready_to_film:
		return
	_t += delta
	_place()


## The sun from behind the camera at the drop-off and a little to one side, so the way up to
## the site is lit, not looked into against the light.
func _light_from_behind(sun: DirectionalLight3D) -> void:
	var ahead := _camera.global_basis * Vector3.FORWARD
	ahead.y = 0.0
	var flat := ahead.normalized().rotated(Vector3.UP, SUN_SIDE)
	sun.global_basis = Basis.looking_at((flat * cos(SUN_HIGH) + Vector3.DOWN * sin(SUN_HIGH)).normalized(), Vector3.UP)


func _place() -> void:
	var zone: Vector3 = _missions.get(&"zone")
	var drop: Vector3 = _missions.call(&"dropoff_of", _missions.get(&"current"))
	var place_info: Dictionary = _missions.call(&"place_of", _missions.get(&"current"))
	if _t < GROUND_SECONDS:
		# Where the group is set down, a few steps back, looking toward the site.
		var up: Vector3 = place_info["up"]
		var at := drop - up * 4.0
		at.y = _terrain.surface_height(at.x, at.z) + EYE
		_camera.global_position = at
		_camera.look_at(Vector3(zone.x, at.y - 1.0, zone.z))
		return
	var from := zone + (drop - zone).normalized() * back
	from.y = zone.y + above
	_camera.global_position = from
	_camera.look_at(zone, Vector3.UP)
