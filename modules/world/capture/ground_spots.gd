extends Node3D
## Capture setup for reviewing how the ground meets roads, tracks and yards (#498): one fixed
## spot on the map, picked with `--spot=farm|cabin|climb|hillside|wide|steep`, lit from behind
## and to one side of the camera so tilted slopes and steps both show.
##   node tools/capture.ts --setup res://modules/world/capture/ground_spots.gd --out x.png
##     --frames 90 --sheet 1 -- --spot=climb

const WORLD := "res://modules/world/scenes/world.tscn"
const SITES := "res://modules/sites/sites_module.gd"
const CAMP := "res://modules/camp/camp_module.gd"
const SUN_SIDE := 0.7
const SUN_HIGH := 0.6

var _camera := Camera3D.new()
var _terrain: VoxelWorld
var _scatter: SceneryScatter


func _ready() -> void:
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	_terrain = world.get_node("Terrain")
	_scatter = world.get_node("Scenery")
	var sites: Node = (load(SITES) as GDScript).new()
	add_child(sites)
	# The camp's fence and yards too, where the highway starts.
	if ResourceLoader.exists(CAMP):
		add_child((load(CAMP) as GDScript).new())
	EventBus.publish(&"world.ready", {"spawn": VoxelWorld.spawn_of(world), "camp": world.get("camp")})
	sites.call(&"build_all")
	_camera.fov = 65.0
	_camera.far = 900.0
	add_child(_camera)
	_camera.current = true
	var spot := "farm"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--spot="):
			spot = a.get_slice("=", 1)
	var view: Array = _view(spot)
	if view.is_empty():
		push_error("ground_spots: no spot %s on this map" % spot)
		return
	var at: Vector3 = view[0]
	var target: Vector3 = view[1]
	_camera.global_position = at
	_camera.look_at(target)
	print("ground_spots: %s camera %s looking at %s" % [spot, at, target])
	_light_from_behind(world.get_node("Sun") as DirectionalLight3D, target - at)
	_camera.add_child(_terrain.make_viewer())
	_terrain.update_around([at, target], INF)
	_scatter.update_around([at, target], INF)


## [camera, look-at] for `spot`, or [] when the map has none.
func _view(spot: String) -> Array:
	match spot:
		"farm":
			return _track_view("farm")
		"cabin":
			var site := _nearest_site("cabin")
			if site.is_empty():
				return []
			var centre: Vector3 = site["centre"]
			var toward: Vector3 = (site["toward"] as Vector3).rotated(Vector3.UP, 0.5)
			var at := centre + toward * 26.0
			at.y = _terrain.ground_height(at.x, at.z) + 3.0
			return [at, centre + Vector3.UP * 1.0]
		"climb":
			return _climb_view()
		"hillside":
			return _hillside_view()
		"steep":
			return _steep_view()
		"wide":
			var home := _terrain.home
			var ahead := _terrain.road_point(500.0)
			var back := (home - ahead)
			back.y = 0.0
			back = back.normalized()
			var at := home + back * 60.0 + Vector3.RIGHT.rotated(Vector3.UP, 0.4) * 20.0
			at.y = _terrain.ground_height(at.x, at.z) + 45.0
			return [at, ahead]
	return []


func _nearest_site(kind: String) -> Dictionary:
	var best := {}
	var best_d := INF
	for s: Dictionary in _terrain.map_site_list():
		if s["kind"] != kind:
			continue
		var d := (s["centre"] as Vector3).distance_to(_terrain.home)
		if d < best_d:
			best_d = d
			best = s
	return best


## Looking along the track that leaves the nearest site of `kind`, from beside it.
func _track_view(kind: String) -> Array:
	var site := _nearest_site(kind)
	if site.is_empty():
		return []
	var index := _terrain.map_site_list().find(site)
	var net: RoadNetwork = (_terrain.heights as MapShape).map["net"]
	for road: Dictionary in net.roads():
		if road["kind"] == "track" and str(road["from"]) == "%s %d" % [kind, index]:
			var line := RoadLine.new(road)
			var s := minf(14.0, line.length() * 0.2)
			var p := line.point_at(s)
			var side := line.across_at(s)
			var at := Vector3(p.x + side.x * 5.0, 0.0, p.y + side.y * 5.0)
			at.y = _terrain.ground_height(at.x, at.z) + 3.2
			var q := line.point_at(minf(s + 40.0, line.length()))
			return [at, Vector3(q.x, line.height_at(minf(s + 40.0, line.length())), q.y)]
	# No track: from the site's front.
	var centre: Vector3 = site["centre"]
	var at2 := centre + (site["toward"] as Vector3) * 30.0 + Vector3.UP * 3.0
	return [at2, centre]


## The steepest stretch of the highway in its first 1.5 km (bridges and tunnels left out),
## seen from below and to one side, looking up it.
func _climb_view() -> Array:
	var net: RoadNetwork = (_terrain.heights as MapShape).map["net"]
	for road: Dictionary in net.roads():
		if road["kind"] != "highway":
			continue
		var line := RoadLine.new(road)
		var spans: Array[Vector2] = []
		for span: Vector2i in (road["tunnels"] as Array) + (road["bridges"] as Array):
			spans.append(Vector2(line.along[maxi(span.x - 1, 0)] - 60.0, line.along[mini(span.y + 1, line.along.size() - 1)] + 60.0))
		var best := -1.0
		var best_s := 0.0
		var s := 40.0
		while s < minf(1500.0, line.length() - 40.0):
			if not spans.any(func(v: Vector2) -> bool: return s > v.x and s < v.y):
				var grade := absf(line.height_at(s + 20.0) - line.height_at(s - 20.0)) / 40.0
				if grade > best:
					best = grade
					best_s = s
			s += 10.0
		# Looking up the hill: from the lower end.
		var up := 1.0 if line.height_at(best_s + 20.0) > line.height_at(best_s - 20.0) else -1.0
		var from := best_s - up * 40.0
		var p := line.point_at(from)
		var side := line.across_at(from)
		# Over the road's edge, clear of the trees kept off it.
		var at := Vector3(p.x + side.x * 3.0, line.height_at(from) + 4.5, p.y + side.y * 3.0)
		var to := best_s + up * 30.0
		var q := line.point_at(to)
		print("ground_spots: steepest highway grade %.3f at %.0f m" % [best, best_s])
		return [at, Vector3(q.x, line.height_at(to), q.y)]
	return []


## The steepest stretch of open ground on the map (steep over 8 m, off roads and sites),
## seen from 30 m downhill: ground that should still step. The map's roads keep off steep
## ground and the ground tilts up to their banks, so none of it lies beside a road.
func _steep_view() -> Array:
	var shape := _terrain.heights as MapShape
	var inside := shape.extent().grow(-100.0)
	var best := -1.0
	var pick := Vector3.ZERO
	var x := inside.position.x
	while x < inside.end.x:
		var z := inside.position.y
		while z < inside.end.y:
			if shape.road_edge_distance(x, z) > 12.0 and not shape.near_site(x, z, {"default": 20.0}) and not shape.in_water(x, z):
				var g := INF
				for d: Vector2 in [Vector2.ZERO, Vector2(4, 0), Vector2(-4, 0), Vector2(0, 4), Vector2(0, -4)]:
					g = minf(g, shape.works.grade(x + d.x, z + d.y))
				if g > best:
					best = g
					pick = Vector3(x, 0.0, z)
			z += 24.0
		x += 24.0
	if best < 0.0:
		return []
	var d := 1.0
	var gx := _terrain.ground_height(pick.x + d, pick.z) - _terrain.ground_height(pick.x - d, pick.z)
	var gz := _terrain.ground_height(pick.x, pick.z + d) - _terrain.ground_height(pick.x, pick.z - d)
	var downhill := -Vector3(gx, 0.0, gz).normalized()
	var look := pick
	look.y = _terrain.ground_height(look.x, look.z)
	var at := pick + downhill.rotated(Vector3.UP, 0.5) * 30.0
	at.y = _terrain.ground_height(at.x, at.z) + 3.0
	print("ground_spots: steep ground grade %.2f at %s" % [best, pick])
	return [at, look]


## Open, gentle, unwooded ground with no road near, looked at across its slope.
func _hillside_view() -> Array:
	var shape := _terrain.heights as MapShape
	var biomes := shape.biomes()
	var home := _terrain.home
	var inside := shape.extent().grow(-150.0)
	var best := Vector3.ZERO
	var best_score := INF
	for j in range(-30, 31):
		for i in range(-30, 31):
			var x := home.x + i * 20.0
			var z := home.z + j * 20.0
			if not inside.has_point(Vector2(x, z)):
				continue
			if shape.road_edge_distance(x, z) < 80.0 or shape.near_site(x, z, {"default": 40.0}) or shape.in_water(x, z):
				continue
			if biomes.forest(x, z) > 0.15:
				continue
			var g := shape.works.grade(x, z)
			# A steady grade near 0.2 over 30 m either way.
			var g2 := shape.works.grade(x + 15.0, z) + shape.works.grade(x - 15.0, z) + shape.works.grade(x, z + 15.0) + shape.works.grade(x, z - 15.0)
			var score := absf(g - 0.2) + absf(g2 / 4.0 - 0.2) + Vector2(x - home.x, z - home.z).length() / 4000.0
			if score < best_score:
				best_score = score
				best = Vector3(x, 0.0, z)
	if best_score == INF:
		return []
	var d := 1.0
	var gx := _terrain.ground_height(best.x + d, best.z) - _terrain.ground_height(best.x - d, best.z)
	var gz := _terrain.ground_height(best.x, best.z + d) - _terrain.ground_height(best.x, best.z - d)
	var downhill := -Vector3(gx, 0.0, gz).normalized()
	# Stand downhill and to one side, looking across and up the slope.
	var look := best
	look.y = _terrain.ground_height(look.x, look.z)
	var at := best + downhill.rotated(Vector3.UP, 0.9) * 28.0
	at.y = _terrain.ground_height(at.x, at.z) + 2.2
	print("ground_spots: hillside at %s grade %.3f" % [best, shape.works.grade(best.x, best.z)])
	return [at, look]


func _light_from_behind(sun: DirectionalLight3D, ahead: Vector3) -> void:
	ahead.y = 0.0
	var flat := ahead.normalized().rotated(Vector3.UP, SUN_SIDE)
	var shine := (flat * cos(SUN_HIGH) + Vector3.DOWN * sin(SUN_HIGH)).normalized()
	sun.global_basis = Basis.looking_at(shine, Vector3.UP)
