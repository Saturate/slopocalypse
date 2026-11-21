extends Node
## The buildings on the map's sites (#493): farmhouses and barns, the cabin, radio masts and
## lookout towers, from per-kind layouts in sites.json, as voxel kit pieces (VoxPiece). Every
## machine builds them from the map on `world.ready` (the map comes from its seed), so nothing
## is sent. A server puts them all up at once; a client a few a frame, nearest first. They
## start solid and are not saved.

var config: Dictionary = {}
var pieces: Array[VoxPiece] = []
## True puts every piece up as soon as the world is ready (a server, which draws nothing).
var all_at_once := DisplayServer.get_name() == "headless"

## Planned pieces not yet put up.
var _queue: Array[Dictionary] = []
## Where the local player started, for building nearest first before a camera exists.
var _near := Vector3.ZERO
var _planned := false


func _ready() -> void:
	var data: Variant = Data.load_json(SiteLayout.CONFIG)
	if not (data is Dictionary and Data.require(SiteLayout.CONFIG, data, SiteLayout.REQUIRED)):
		return
	var problems := SiteLayout.check(data)
	for problem in problems:
		Log.error(&"sites", "%s: %s" % [SiteLayout.CONFIG, problem])
	if not problems.is_empty():
		return
	config = data
	EventBus.subscribe(&"world.ready", _on_world_ready)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"world.ready", _on_world_ready)


func _on_world_ready(p: Dictionary) -> void:
	if _planned or config.is_empty():
		return
	# The flat test world has no sites.
	var ground := get_tree().get_first_node_in_group(&"ground")
	if ground == null or not ground.has_method(&"map_site_list"):
		return
	_planned = true
	_near = p.get("spawn", Vector3.ZERO)
	var sites: Array = ground.call(&"map_site_list")
	_queue = SiteLayout.plan(sites, config)
	# The world draws the yards (packed dirt from the track up to the buildings) like its
	# tracks; only this module knows where the buildings stand.
	var scenery := get_tree().get_first_node_in_group(&"scenery")
	if scenery != null and scenery.has_method(&"set_yards_for"):
		scenery.call(&"set_yards_for", &"sites", SiteLayout.yards(sites, config))
	if all_at_once:
		build_all()


func pending() -> int:
	return _queue.size()


func build_all() -> void:
	var t := Prof.start()
	while not _queue.is_empty():
		_put_up(_queue.pop_front())
	Prof.stop(&"sites/build", t)


func _process(_delta: float) -> void:
	if _queue.is_empty():
		return
	var t := Prof.start()
	var camera := get_viewport().get_camera_3d()
	var near := camera.global_position if camera != null else _near
	for i in maxi(int(config["builds_per_frame"]), 1):
		if _queue.is_empty():
			break
		_put_up(_queue.pop_at(_nearest(near)))
	Prof.stop(&"sites/build", t)


func _nearest(to: Vector3) -> int:
	var best := 0
	var best_d := INF
	for i in _queue.size():
		var d := to.distance_squared_to((_queue[i]["transform"] as Transform3D).origin)
		if d < best_d:
			best_d = d
			best = i
	return best


func _put_up(p: Dictionary) -> void:
	var piece := VoxPiece.new()
	piece.name = "%s%d" % [str(p["kind"]).to_pascal_case(), pieces.size()]
	piece.generator = p["generator"]
	piece.params = p["params"]
	piece.transform = p["transform"]
	piece.set_meta(&"site_kind", p["kind"])
	add_child(piece)
	pieces.append(piece)
