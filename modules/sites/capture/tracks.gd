extends Node3D
## Capture setup: the dirt tracks into the default map's first farm, cabin and lookout, each
## seen twice: from eye height on the track looking in at the site, and from a few metres
## over the track looking down at its surface. TRACK_VIEW=wide stands further back and
## higher instead, TRACK_VIEW=yard looks down onto the site's yard; TRACK_STOP=n holds one
## stop (for a single full-size frame).

const WORLD := "res://modules/world/scenes/world.tscn"
const MODULE := "res://modules/sites/sites_module.gd"
const KINDS := ["farm", "cabin", "lookout"]
## Frames each stop is held; the sheet grabs every 20th frame (120 frames, 6 cells), so the
## stop changes 5 frames after a grab and each grab sees a stop settled for 15 frames. Counted
## in engine frames, as the capture tool counts them, however long the world takes to load.
const FRAMES_PER_STOP := 20
const SHIFT := 5

var _camera := Camera3D.new()
var _terrain: VoxelWorld
var _scatter: SceneryScatter
## Per stop: [eye, look at].
var _stops: Array[Array] = []
var _hold := -1
var _shown := -1


func _ready() -> void:
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	_terrain = world.get_node("Terrain")
	_scatter = world.get_node("Scenery")
	var sites: Node = (load(MODULE) as GDScript).new()
	add_child(sites)
	EventBus.publish(&"world.ready", {"spawn": VoxelWorld.spawn_of(world)})
	sites.call(&"build_all")
	var wide := OS.get_environment("TRACK_VIEW") == "wide"
	var yard := OS.get_environment("TRACK_VIEW") == "yard"
	_hold = int(OS.get_environment("TRACK_STOP")) if OS.has_environment("TRACK_STOP") else -1
	var net: RoadNetwork = (_terrain.heights as MapShape).map["net"]
	var list := _terrain.map_site_list()
	for kind: String in KINDS:
		for i in list.size():
			if list[i]["kind"] != kind:
				continue
			var line := _track_of(net, "%s %d" % [kind, i])
			if line == null:
				continue
			_add_stops(line, list[i], wide, yard)
			break
	if _stops.is_empty():
		push_error("no site tracks on this map")
		return
	_camera.fov = 70.0
	_camera.far = 900.0
	add_child(_camera)
	_camera.current = true
	_camera.add_child(_terrain.make_viewer())
	(world.get_node("Sun") as DirectionalLight3D).rotation_degrees = Vector3(-55.0, 35.0, 0.0)
	_go(maxi(_hold, 0))


func _track_of(net: RoadNetwork, name: String) -> RoadLine:
	for road: Dictionary in net.roads():
		if road["kind"] == "track" and road["from"] == name:
			return RoadLine.new(road)
	return null


func _add_stops(line: RoadLine, site: Dictionary, wide: bool, yard: bool) -> void:
	var centre: Vector3 = site["centre"]
	var on := func(s: float, up: float) -> Vector3:
		var p := line.point_at(s)
		return Vector3(p.x, _terrain.surface_height(p.x, p.y) + up, p.y)
	if wide:
		_stops.append([on.call(70.0, 14.0), centre])
		_stops.append([on.call(140.0, 40.0), on.call(40.0, 0.0)])
		return
	if yard:
		# Down onto the yard from a little to one side of the track, then from straight above.
		var toward: Vector3 = site["toward"]
		var side := toward.cross(Vector3.UP)
		var reach := (site["footprint"] as Rect2).size.length() * 0.45
		_stops.append([centre + toward * reach + side * reach * 0.4 + Vector3.UP * reach * 0.35, centre])
		_stops.append([centre + toward * reach * 0.3 + Vector3.UP * reach * 1.1, centre + toward * reach * 0.05])
		return
	# Eye height on the track, looking in at the site.
	_stops.append([on.call(14.0, 1.7), centre + Vector3.UP * 1.5])
	# Over the track looking down at its surface, a little ahead.
	_stops.append([on.call(30.0, 4.5), on.call(22.0, 0.0)])


func _process(_delta: float) -> void:
	if _stops.is_empty():
		return
	var stop := clampi((Engine.get_process_frames() - SHIFT) / FRAMES_PER_STOP, 0, _stops.size() - 1)
	if _hold < 0 and stop != _shown:
		_go(stop)


func _go(stop: int) -> void:
	_shown = stop
	var view: Array = _stops[mini(stop, _stops.size() - 1)]
	var at: Vector3 = view[0]
	_camera.global_position = at
	_camera.look_at(view[1])
	_scatter.update_around([at], INF)
	_terrain.update_around([at], INF)
