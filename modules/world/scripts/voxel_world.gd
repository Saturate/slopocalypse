class_name VoxelWorld
extends Node3D
## The ground: blocky voxel columns over the generated map (MapShape), streamed in 32 m tiles
## around whoever needs them, and diggable.
##
## The server builds collision tiles (height maps of the smooth ground, with craters cut in)
## around every player, enemy, vehicle and terrain viewer, so nobody's ground depends on
## anyone else's. Clients build the visible voxel tiles around their camera, finer close by
## and coarser far away. Both apply the same digs from the same replayed events.

const SHADER := "res://modules/world/shaders/voxel_ground.gdshader"
const VOXEL_REQUIRED := {"max_dig_depth": TYPE_FLOAT, "crater_depth_share": TYPE_FLOAT, "collision_distance": TYPE_FLOAT, "load_distance": TYPE_FLOAT, "lods": TYPE_ARRAY, "build_budget_ms": TYPE_FLOAT}
const GROUND_REQUIRED := {"tilt_grade": TYPE_FLOAT, "band": TYPE_FLOAT, "pad_band": TYPE_FLOAT, "band_grade": TYPE_FLOAT, "ledge": TYPE_FLOAT, "ledge_grade": TYPE_FLOAT, "wall_light": TYPE_FLOAT, "tilt_variation": TYPE_FLOAT, "track_fray": TYPE_FLOAT, "track_verge": TYPE_FLOAT, "yard_fray": TYPE_FLOAT, "yard_round": TYPE_FLOAT, "lane_soil": TYPE_ARRAY, "lane_mix": TYPE_FLOAT, "verge_mix": TYPE_FLOAT, "rut_dark": TYPE_FLOAT}
const TILE := 32.0
## Collision height maps sample the ground every metre.
const COLLISION_SPACING := 1.0
## Ground colours are sampled this far apart and dithered between per voxel.
const COLOUR_SPACING := 4.0
## Steeper than this (rise over run) shows bare rock.
const STEEP_SLOPE := 1.1
const SKIRT := 2.0
## A dent this deep counts as dug: lanes and strips leave its earth unpainted.
const DUG_DEPTH := 0.2
## Floats per way segment `VoxelGround.tile_arrays` takes, and the kind that paints a lane
## with square ends (a yard).
const WAY_STRIDE := 8
const WAY_YARD := 3
const WAY_PAD := 4
## Focus points closer together than this (metres) count as one.
const THIN_GRID := 4.0
## Ground this close to a focus point (metres) is built whatever the frame's budget: someone
## stands on it or is about to.
const URGENT_REACH := 8.0
## Tiles of each kind (collision, visible) being sampled or meshed at once: enough to keep the
## threads busy, few enough that tiles queued for where someone was don't hold up the ones
## where they are now, and that starting them never takes long in one frame.
const MAX_JOBS := 12
const GRASS := Color(0.36, 0.5, 0.22)
const LITTER := Color(0.33, 0.29, 0.18)
const STRAW := Color(0.7, 0.61, 0.36)
const STONE := Color(0.5, 0.49, 0.46)
const SAND := Color(0.78, 0.71, 0.52)
const ROCK := Color(0.44, 0.48, 0.54)
const SOIL := Color(0.42, 0.31, 0.2)
const DIRT := Color(0.38, 0.28, 0.18)

## A hole was dug (after clamping), so grass over it can go.
signal dug(center: Vector3, radius: float)
## A crater next to a pond filled with its water: Vector4(x, z, radius at the surface, level).
signal flooded(puddle: Vector4)

@export_file("*.json") var config_path: String = "res://modules/world/data/world.json"

## The map's land; null when no map could be built.
var heights: GroundShape
## Where players start (the map's camp): always kept built.
var home := Vector3.ZERO
var max_dig_depth := 3.0
## A crater's depth as a share of its radius. Its wall is steepest at the rim, a slope of
## twice this share: 0.35 gives about 35 degrees, under the 45 a player can walk up, with
## room for a hillside's own slope on the uphill wall.
var crater_depth_share := 0.35

var _biomes: GroundBiomes
var _cfg: Dictionary
## [[distance, voxel size], ...] nearest first.
var _lods: Array = []
var _visual := DisplayServer.get_name() != "headless"
var _collision: Dictionary[Vector2i, StaticBody3D] = {}
var _tiles: Dictionary[Vector2i, MeshInstance3D] = {}
var _tile_voxel: Dictionary[Vector2i, float] = {}
## Craters (x, y, z, radius), listed under every tile they reach, so a height sample only
## looks at the few near it however many have been dug.
var _digs_in: Dictionary[Vector2i, Array] = {}
## Every dig in order (Vector4: centre, radius), for late joiners and the save; the oldest go
## first past `max_dig_log` (they're also the most likely to have been dug over since).
var _dig_log: Array[Vector4] = []
var max_dig_log := 4000
## How far past the road's edge a levelled pad fades out, metres.
const PAD_ROAD_GAP := 1.0
## Levelled pads (`set_pads`), listed under every tile they reach like craters.
var _pads_in: Dictionary[Vector2i, Array] = {}
## Untouched ground heights per collision tile, so a crater only re-applies craters.
var _base_heights: Dictionary[Vector2i, PackedFloat32Array] = {}
var _material: ShaderMaterial
## The light whose bounce the ground's walls show, and what the shader was last told of it.
var _sun: DirectionalLight3D
var _daylight := Vector3(-1.0, -1.0, -1.0)
var _to_sun := Vector3.ZERO
## The focus tiles last time, and whether the build budget ran out then (work left to do).
var _last_focus: Array[Vector2i] = []
var _pending := true
## Height samples being worked out on worker threads: collision tile -> {task, result}, and
## visible tile -> {task, result, voxel}. Results are an Array the task appends to.
var _base_jobs: Dictionary[Vector2i, Dictionary] = {}
var _tile_jobs: Dictionary[Vector2i, Dictionary] = {}
## Visible tiles whose craters, pads or lanes changed since they were built: rebuilt in turn,
## the old one showing until then.
var _stale: Dictionary[Vector2i, bool] = {}
## Bumped whenever a tile's craters, pads or lanes change, so a job started before is not used.
var _tile_gen: Dictionary[Vector2i, int] = {}
## The visible tiles wanted ({tile: distance}) and the same nearest first as Vector4(distance,
## x, z, voxel size), for the focus tiles `_order_focus`.
var _wanted_tiles := {}
var _tile_order: Array[Vector4] = []
var _order_focus: Array[Vector2i] = []
## The list being made on a worker thread (`_advance_list`): {task, result, focus, points}.
var _list_job := {}
## The collision tiles wanted ({tile: distance}) and the same nearest first as Vector3(distance,
## x, z), for the focus tiles `_collision_focus`.
var _collision_wanted := {}
var _collision_order: Array[Vector3] = []
var _collision_focus: Array[Vector2i] = []
## How the visible ground tilts and draws roads, tracks and lanes (world.json `ground`, as
## `VoxelGround.tile_arrays` takes it).
var _look := {}
## Lanes painted into the ground by who laid them (`set_lanes_for`), and the same as way
## segments (world metres, `Earthworks.segments_near`'s layout) under every tile they reach.
var _lane_sets: Dictionary[StringName, Array] = {}
var _lanes_in: Dictionary[Vector2i, PackedFloat32Array] = {}
## How far past a lane's edge it may still change the ground, metres.
var _lane_margin := 2.0
## The distant land's grid (metres) and how far out, as a share of the load distance, it takes
## over from the voxel ground: short of the edge, so no gap opens between them.
const FAR_STEP := 16.0
const FAR_CUT := 0.85
## See `sea_depth_limit`.
var _sea_depth_limit := INF


func _ready() -> void:
	var data: Variant = Data.load_json(config_path)
	if not data is Dictionary:
		return
	var world: Dictionary = data
	if not world.has("voxel") or not Data.require(config_path + " voxel", world["voxel"], VOXEL_REQUIRED):
		return
	_cfg = world["voxel"]
	max_dig_depth = _cfg["max_dig_depth"]
	crater_depth_share = _cfg["crater_depth_share"]
	max_dig_log = int(_cfg.get("max_saved_digs", 4000))
	_lods = _cfg["lods"]
	if not world.has("ground") or not Data.require(config_path + " ground", world["ground"], GROUND_REQUIRED):
		return
	_look = (world["ground"] as Dictionary).duplicate()
	_look.erase("_comment")
	var soil: Array = _look["lane_soil"]
	_look["lane_soil"] = Color(float(soil[0]), float(soil[1]), float(soil[2]))
	# What shows through a strip where it is worn or shot through: the strip's own bed, and
	# how far the strip's surface stands over its road's height.
	_look["paved_bed"] = VoxRoad.GRAVEL
	_look["track_soil"] = SceneryScatter.TRACK_SOIL
	# The model fills whole voxels by their centres: its surface is the top of the last cell
	# whose centre is under BED + SURFACE.
	var road_v := SceneryScatter.ROAD_VOXEL
	_look["strip_top"] = (floorf((VoxRoad.BED + VoxRoad.SURFACE) / road_v - 0.5) + 1.0) * road_v - SceneryScatter.ROAD_LIFT
	_look["steep_slope"] = STEEP_SLOPE
	_look["steep"] = ROCK
	_look["side"] = SOIL
	_look["skirt"] = SKIRT
	# A lane's verge and frayed edge reach a cell of the coarsest detail past its edge.
	_lane_margin = float((_lods[-1] as Array)[1]) + float(_look["track_fray"])
	# The world module selects the map; built on its own (a test, a capture) it is world.json's.
	var map := WorldMaps.shape_or_default()
	if map == null:
		Log.error(&"world", "no map to build the ground from (%s)" % WorldMaps.recipe_name())
		return
	heights = map
	_biomes = map.biomes()
	var sea: Variant = (world.get("water", {}) as Dictionary).get("sea")
	if sea is Dictionary and map.land.has_coast():
		_sea_depth_limit = float((sea as Dictionary).get("depth_limit", INF))
	home = map.camp()
	# Other modules place things on the ground where no tile is built (the server only builds
	# near players): `ground_height` answers anywhere.
	add_to_group(&"ground")
	if _visual:
		_material = ShaderMaterial.new()
		_material.shader = load(SHADER)
		_material.set_shader_parameter(&"tilt_variation", float(_look["tilt_variation"]))
		_material.set_shader_parameter(&"wall_light", float(_look["wall_light"]))
		_material.set_shader_parameter(&"paint_grain", SceneryScatter.ROAD_VOXEL)
		_material.set_shader_parameter(&"paint_jitter", VoxRoad.DIRT_JITTER)
		# Always there, even with no ponds: others pour puddles on the ground through it.
		var view := WaterView.new()
		view.name = "Water"
		view.water = heights.water
		view.config = world.get("water", {})
		add_child(view)
		flooded.connect(view.add_puddle)
		var far := FarLand.new()
		far.name = "FarLand"
		far.build(heights, FAR_STEP, float(_cfg["load_distance"]) * FAR_CUT, func(x: float, z: float) -> Color: return _colour_at(x, z, [], []))
		add_child(far)
	# The spawn is solid before anyone arrives.
	update_around([home], INF)


func _process(_delta: float) -> void:
	var prof := Prof.start()
	_process_tick(_delta)
	Prof.stop(&"world/voxel_world:frame", prof)


func _process_tick(_delta: float) -> void:
	if heights == null:
		return
	update_around(_focus_points(), float(_cfg["build_budget_ms"]), true)
	_follow_sun()


## The ground's walls take bounced light from the world's sun (the day cycle moves and dims
## it), so the shader is told its light and where it is.
func _follow_sun() -> void:
	if _material == null:
		return
	if _sun == null or not is_instance_valid(_sun):
		# A scene with no sun (some captures) would be searched every frame otherwise.
		if Engine.get_process_frames() % 60 != 0:
			return
		_sun = get_tree().get_first_node_in_group(&"sun") as DirectionalLight3D
		if _sun == null:
			return
	var light := Vector3(_sun.light_color.r, _sun.light_color.g, _sun.light_color.b) * _sun.light_energy
	if not _sun.visible:
		light = Vector3.ZERO
	var toward := _sun.global_basis.z.normalized()
	if light.is_equal_approx(_daylight) and toward.is_equal_approx(_to_sun):
		return
	_daylight = light
	_to_sun = toward
	_material.set_shader_parameter(&"daylight", light)
	_material.set_shader_parameter(&"to_sun", toward)


## On a client, its own player; null on a server or offline. A client streams ground round
## its camera only (the server follows everyone), so one with no camera (headless: playtests
## with --headless, bots, net tests) follows this instead, or it builds nothing but the camp.
static func own_player_on_client(node: Node) -> Node3D:
	var mp := node.multiplayer
	if not mp.has_multiplayer_peer() or mp.is_server():
		return null
	var me := mp.get_unique_id()
	for n in node.get_tree().get_nodes_in_group(&"players"):
		if n is Node3D and int(n.get_meta(&"peer_id", 0)) == me:
			return n as Node3D
	return null


## Where a client's own player counts as being (`PlayerSpot`: the car, once they drive), or
## null when it has none. A seated body stays where it got in, so following the body built
## nothing round a headless driver once the car left.
static func own_spot_on_client(node: Node) -> Variant:
	var own := own_player_on_client(node)
	if own == null:
		return null
	return PlayerSpot.of(own, PlayerSpot.cars_api(node.get_tree()))


## A marker that keeps the ground built around it (for cameras in captures and harnesses;
## the camera, or a headless client's own player, and on the server every player, enemy and
## vehicle are followed already).
func make_viewer() -> Node3D:
	var viewer := Node3D.new()
	viewer.name = "VoxelViewer"
	viewer.add_to_group(&"terrain_focus")
	return viewer


## For captures and harnesses: adds the world scene under `parent` and waits until the
## spawn area is solid.
static func add_and_wait(parent: Node, scene_path: String, max_frames: int = 900) -> Node3D:
	var world: Node3D = (load(scene_path) as PackedScene).instantiate()
	parent.add_child(world)
	var voxels: VoxelWorld = world.get_node("Terrain")
	for i in max_frames:
		if voxels.is_ready_at(voxels.home):
			break
		await parent.get_tree().physics_frame
	return world


## For captures and harnesses: the point `offset` across the ground from `world`'s spawn (the
## map's camp, far from the origin), `offset.y` above the untouched ground there.
static func spawn_of(world: Node, offset := Vector3.ZERO) -> Vector3:
	var voxels: VoxelWorld = world.get_node("Terrain")
	var spawn := world.get_node_or_null("SpawnPoint") as Node3D
	var at := (spawn.global_position if spawn != null else voxels.home) + Vector3(offset.x, 0.0, offset.z)
	at.y = voxels.ground_height(at.x, at.z) + offset.y
	return at


## True once the ground around `point` has collision.
func is_ready_at(point: Vector3, radius: float = 8.0) -> bool:
	if heights == null:
		return false
	var low := _tile_of(point - Vector3(radius, 0, radius))
	var high := _tile_of(point + Vector3(radius, 0, radius))
	for tx in range(low.x, high.x + 1):
		for tz in range(low.y, high.y + 1):
			if not _collision.has(Vector2i(tx, tz)):
				return false
	return true


## How deep the water is at `position` (0 outside every pond): its level less the ground
## under it. From the world data, so the server and every client agree without sending it.
## Craters included: one in a pond is deeper water, one beside it may have flooded.
func water_depth_at(position: Vector3) -> float:
	var level := water_level_at(position)
	if is_nan(level):
		return 0.0
	return maxf(level - surface_height(position.x, position.z), 0.0)


## How deep the sea is at `position` (#454): 0 off the sea (on land, in a pond or a flooded
## crater). From the world data, as `water_depth_at`.
func sea_depth_at(position: Vector3) -> float:
	if not heights is MapShape or not (heights as MapShape).land.is_sea(position.x, position.z):
		return 0.0
	return maxf((heights as MapShape).sea_level() - surface_height(position.x, position.z), 0.0)


## Metres of sea under a swimmer past which they tire (world.json water.sea depth_limit);
## INF without one.
func sea_depth_limit() -> float:
	return _sea_depth_limit


## The surface of the water at `position`'s x and z (a pond or a flooded crater), or NAN.
func water_level_at(position: Vector3) -> float:
	if heights == null:
		return NAN
	return heights.water.level_at(position.x, position.z)


## Where the map's city stands (see MapShape.city); empty without one.
func map_city() -> Dictionary:
	return (heights as MapShape).city() if heights is MapShape else {}


## Whether this is a generated map (not the flat test world, whose ground is FlatGround).
func on_map() -> bool:
	return heights is MapShape


## The centres of the map's sites of `kind` (see MapShape.sites).
func map_sites(kind: String) -> Array[Vector3]:
	return (heights as MapShape).sites(kind) if heights is MapShape else ([] as Array[Vector3])


## Every site of the map with its footprint and the way its track leaves (see
## MapShape.site_list); empty off the map.
func map_site_list() -> Array[Dictionary]:
	return (heights as MapShape).site_list() if heights is MapShape else ([] as Array[Dictionary])


## The map's power lines and substation (see MapShape.power_lines, power_substation); empty
## off the map.
func map_power_lines() -> Array[Dictionary]:
	return (heights as MapShape).power_lines() if heights is MapShape else ([] as Array[Dictionary])


func map_power_substation() -> Dictionary:
	return (heights as MapShape).power_substation() if heights is MapShape else {}


## Height of the untouched ground (ignores digging) for placing spawns and scenery.
func ground_height(x: float, z: float) -> float:
	return heights.height_at(x, z) if heights != null else 0.0


## A point `metres` along the highway from the camp, on the untouched ground; the far end
## of the highway if it is shorter than that.
func road_point(metres: float) -> Vector3:
	if heights is MapShape:
		return (heights as MapShape).road_point(metres)
	return home + Vector3(0.0, 0.0, -metres)


## How long the highway from the camp is, metres (INF off the map, where `road_point` runs on).
func road_length() -> float:
	if not heights is MapShape:
		return INF
	var points := (heights as MapShape).highway()
	var length := 0.0
	for k in range(1, points.size()):
		length += points[k].distance_to(points[k - 1])
	return length


## The ground as it is now: levelled pads and craters included.
func surface_height(x: float, z: float) -> float:
	var key := _tile_of(Vector3(x, 0.0, z))
	return _dig_into(_pad_into(ground_height(x, z), x, z, _pads_in.get(key, [])), x, z, _digs_in.get(key, []))


## The ground with levelled pads but without craters: for what is put up on it alike on
## every machine whenever it joins.
func levelled_height(x: float, z: float) -> float:
	return _pad_into(ground_height(x, z), x, z, _pads_in.get(_tile_of(Vector3(x, 0.0, z)), []))


## Pad sets by who owns them (missions, the city...): each owner replaces only its own.
var _pad_sets: Dictionary[StringName, Array] = {}


## `owner`'s pads (see `set_pads`), replacing that owner's earlier ones and keeping everyone
## else's.
func set_pads_for(owner: StringName, pads: Array) -> void:
	_pad_sets[owner] = pads
	var all: Array = []
	for key: StringName in _pad_sets:
		all.append_array(_pad_sets[key])
	_apply_pads(all)


## Whether a circle of `radius` at `at` reaches onto a pad of an owner other than `owner`
## (its blend included), or onto a map site's pad: ground someone else has levelled for what
## stands there. The site pad `except_site` (the one a mission builds round at its level)
## does not count.
func is_claimed(at: Vector3, radius: float, owner: StringName, except_site := Rect2()) -> bool:
	# A map site's pad is held by what stands on it (sites, towers) for everyone.
	if heights is MapShape and (heights as MapShape).site_within(at.x, at.z, radius, except_site):
		return true
	# So is ground under a power line's towers and the substation's yard.
	if heights is MapShape and (heights as MapShape).power_within(at.x, at.z, radius):
		return true
	for key: StringName in _pad_sets:
		if key == owner:
			continue
		for p: Dictionary in _pad_sets[key]:
			var centre: Vector3 = p["at"]
			var half: Vector2 = p["half"]
			var reach := float(p.get("blend", 3.0)) + radius
			var local := Basis(Vector3.UP, float(p.get("yaw", 0.0))).inverse() * (at - centre)
			if absf(local.x) < half.x + reach and absf(local.z) < half.y + reach:
				return true
	return false


## Whether a circle of `radius` at `at` reaches within `margin` of a road's or track's edge.
func near_road(at: Vector3, radius: float, margin: float) -> bool:
	return heights != null and heights.near_road(at.x, at.z, radius + margin)


## Pads for callers that name no owner (the missions).
func set_pads(pads: Array) -> void:
	set_pads_for(&"", pads)


## Levels the ground under footprints (mission buildings), replacing any earlier set. Each
## pad is `{at: Vector3, half: Vector2, yaw: float, blend: float}`: a rectangle `half` either
## side of `at` (x across, y along, turned by `yaw` like a node's rotation.y) flat at `at.y`,
## easing back into the natural ground over `blend` metres. With `from` (a height) it is a
## ramp instead: `from` at its -z end rising or falling evenly to `at.y` at its +z end.
## Raises and lowers alike; craters still dig into it. Every instance sets the same pads from
## the same layout, so nothing about it is sent.
func _apply_pads(pads: Array) -> void:
	var touched: Dictionary[Vector2i, bool] = {}
	for key: Vector2i in _pads_in:
		touched[key] = true
	_pads_in.clear()
	for p: Dictionary in pads:
		var at: Vector3 = p["at"]
		var half: Vector2 = p["half"]
		var yaw := float(p.get("yaw", 0.0))
		var pad := {"x": at.x, "z": at.z, "h": at.y, "from": float(p.get("from", at.y)), "hx": half.x, "hz": half.y, "c": cos(yaw), "s": sin(yaw), "blend": maxf(0.01, float(p.get("blend", 3.0)))}
		var reach := half.length() + float(pad["blend"])
		var low := _tile_of(at - Vector3(reach, 0, reach))
		var high := _tile_of(at + Vector3(reach, 0, reach))
		for tx in range(low.x, high.x + 1):
			for tz in range(low.y, high.y + 1):
				var key := Vector2i(tx, tz)
				if not _pads_in.has(key):
					_pads_in[key] = []
				_pads_in[key].append(pad)
				touched[key] = true
	for key: Vector2i in touched:
		if _collision.has(key):
			_collision[key].queue_free()
			_collision[key] = _build_collision(key)
		_touch(key)


## `h` levelled towards any of `pads` over (x, z): their height inside, easing out to `h`.
## The road keeps its own level: pads fade out over a metre past the road's edge.
func _pad_into(h: float, x: float, z: float, pads: Array) -> float:
	if pads.is_empty():
		return h
	# How much the pads may level here: 0 on a road (it keeps its own level), 1 from
	# `PAD_ROAD_GAP` metres past its edge. Looked up only once a pad reaches this sample:
	# this runs for every ground sample in a tile with a pad, and most lie outside them.
	var road_share := -1.0
	for p: Dictionary in pads:
		var dx := x - float(p["x"])
		var dz := z - float(p["z"])
		# Into the pad's own frame (the inverse of turning by its yaw about up).
		var lx := dx * float(p["c"]) - dz * float(p["s"])
		var lz := dx * float(p["s"]) + dz * float(p["c"])
		var out := Vector2(maxf(absf(lx) - float(p["hx"]), 0.0), maxf(absf(lz) - float(p["hz"]), 0.0)).length()
		var weight := 1.0 - smoothstep(0.0, float(p["blend"]), out)
		if weight <= 0.0:
			continue
		if road_share < 0.0:
			road_share = smoothstep(0.0, PAD_ROAD_GAP, heights.road_edge_distance(x, z)) if heights != null else 1.0
		weight *= road_share
		var level := float(p["h"])
		if float(p["from"]) != level:
			level = lerpf(float(p["from"]), level, clampf(lz / float(p["hz"]) * 0.5 + 0.5, 0.0, 1.0))
		h = lerpf(h, level, weight)
	return h


## `h` lowered by any of `digs` over (x, z). A crater is a dent in the surface it was blasted
## into, not a hole cut to a fixed height: deepest in the middle and easing to nothing at its
## rim. Its wall is never steeper than the ground under it plus one bowl, wherever it is, and
## overlapping dents take the lowest of them, so nobody is trapped in one and repeated blasts
## can't dig a well. Each dig is (x, depth, z, radius).
func _dig_into(h: float, x: float, z: float, digs: Array) -> float:
	var out := h
	for d: Vector4 in digs:
		var dx := x - d.x
		var dz := z - d.z
		var r2 := d.w * d.w
		var d2 := dx * dx + dz * dz
		if d2 < r2:
			out = minf(out, h - d.y * (1.0 - d2 / r2))
	return out


## Dents the ground (see `_dig_into`). Runs on the server and on every client from the same
## replayed event, so all of them dig the same hole. A blast on the ground dents it
## `radius * crater_depth_share` deep (never more than `max_dig_depth`); one in the air dents
## it less by its height, and one under the surface (in a crater already) no deeper.
func server_dig(at: Vector3, radius: float) -> void:
	if heights == null:
		return
	var surface := _pad_into(ground_height(at.x, at.z), at.x, at.z, _pads_in.get(_tile_of(at), []))
	var most := minf(radius * crater_depth_share, max_dig_depth)
	_dent(at.x, at.z, clampf(most - (at.y - surface), 0.0, most), radius)


## A dig from `dig_log` again (a late joiner, a restart): the same dent the server made,
## whatever pads this instance has set by now.
func replay_dig(logged: Vector4) -> void:
	if heights == null:
		return
	var most := minf(logged.w * crater_depth_share, max_dig_depth)
	_dent(logged.x, logged.z, clampf(most - (logged.y - ground_height(logged.x, logged.z)), 0.0, most), logged.w)


func _dent(x: float, z: float, depth: float, radius: float) -> void:
	if depth <= 0.0:
		return
	var surface := _pad_into(ground_height(x, z), x, z, _pads_in.get(_tile_of(Vector3(x, 0.0, z)), []))
	var center := Vector3(x, surface, z)
	# Logged as the blast height over the untouched ground that gives this depth, so a replay
	# (`replay_dig`) needs nothing that can differ between instances, such as pads.
	var most := minf(radius * crater_depth_share, max_dig_depth)
	_dig_log.append(Vector4(x, ground_height(x, z) + most - depth, z, radius))
	if _dig_log.size() > max_dig_log:
		_dig_log.remove_at(0)
	var dig := Vector4(x, depth, z, radius)
	var low := _tile_of(center - Vector3(radius, 0, radius))
	var high := _tile_of(center + Vector3(radius, 0, radius))
	for tx in range(low.x, high.x + 1):
		for tz in range(low.y, high.y + 1):
			var key := Vector2i(tx, tz)
			if not _digs_in.has(key):
				_digs_in[key] = []
			_digs_in[key].append(dig)
			# Collision right away: whoever stands there falls into the crater now. The
			# visible tile follows within a frame or two, off the main thread.
			if _collision.has(key):
				_collision[key].queue_free()
				_collision[key] = _build_collision(key)
			_touch(key)
	var puddle := heights.water.flood(center, radius, depth)
	if puddle != Vector4.ZERO:
		flooded.emit(puddle)
	dug.emit(center, radius)


## Every dig so far, oldest first, for `replay_dig`: (x, y, z, radius), y being the blast
## height over the untouched ground that dents the ground as deep as the dig did.
func dig_log() -> Array[Vector4]:
	return _dig_log


## Builds collision and visible tiles near `points` and frees far ones. Right away, `budget`
## is how many tiles this call may build. With `threaded` it is milliseconds of this frame:
## ground is sampled on worker threads and meshed on VoxelGround's mesher threads, and this
## call only starts jobs and puts finished tiles in, nearest first, until the time is up. The
## ground within URGENT_REACH of a point goes in whatever the budget, so nobody stands where
## there is none.
func update_around(points: Array[Vector3], budget: float, threaded := false) -> void:
	# Many focus points stand close together (a squad, a player in a car): one per few metres
	# is plenty, and fewer points make every distance below cheaper.
	points = _thin(points)
	# Nothing moved to another tile and nothing was left to build last time: nothing to do.
	# This runs every frame, so the common case has to be nearly free.
	var focus := _focus_key(points)
	if focus == _last_focus and not _pending:
		return
	_last_focus = focus
	# Past a day of milliseconds a budget means "no limit" (and keeps the sum in an int).
	var deadline := Time.get_ticks_usec() + int(minf(budget, 8.64e7) * 1000.0) if threaded else -1
	# Clients build collision too (around their camera): cheap, and the world announces
	# itself only once the spawn is solid, on every machine.
	var built := _update_collision(points, budget, deadline)
	_pending = built < 0.0 or not _base_jobs.is_empty()
	if _visual:
		# The first step of the call is the tiles' if collision had nothing to do.
		_pending = _update_tiles(points, budget - built if built >= 0.0 else 0.0, deadline, built == 0.0) or _pending or not _tile_jobs.is_empty()


## True once the time (threaded) or the count of builds (right away) is used up. Threaded,
## the call's first build is always made, so even a budget of nothing gets somewhere: steps
## that only start a job or hand samples to a mesher (cheap) don't use up that first build,
## though once the time is up they wait for the next call too.
func _spent(built: float, budget: float, deadline: int, first: bool) -> bool:
	if deadline >= 0:
		return not first and Time.get_ticks_usec() >= deadline
	return built >= budget


## Builds missing collision tiles nearest first; how many it built, or -1 when it stopped
## with some still to build.
func _update_collision(points: Array[Vector3], budget: float, deadline: int) -> float:
	var reach: float = _cfg["collision_distance"]
	var tl := Prof.start()
	if _collision_focus != _last_focus:
		_collision_focus = _last_focus
		_collision_wanted = _tiles_near(points, reach)
		_collision_order.clear()
		for key: Vector2i in _collision_wanted:
			_collision_order.append(Vector3(_collision_wanted[key], key.x, key.y))
		_collision_order.sort()
	Prof.stop(&"world/voxel_world/collision_list", tl)
	var wanted := _collision_wanted
	var built := 0.0
	var left := false
	var first := true
	for entry in _collision_order:
		var key := Vector2i(int(entry.y), int(entry.z))
		if _collision.has(key):
			continue
		var urgent := entry.x <= URGENT_REACH
		if not urgent and _spent(built, budget, deadline, first):
			left = true
			break
		if not _base_heights.has(key) and _base_jobs.has(key) and WorkerThreadPool.is_task_completed(int(_base_jobs[key]["task"])):
			_take_base(key)
		# Ground under someone is sampled right here if its job hasn't finished: a body must
		# never stand where there is no collision.
		if deadline >= 0 and not urgent and not _base_heights.has(key):
			if not _base_jobs.has(key) and _base_jobs.size() < MAX_JOBS:
				_start_base(key)
			continue
		var tc := Prof.start()
		_collision[key] = _build_collision(key)
		Prof.stop(&"world/voxel_world/collision", tc)
		built += 1.0
		first = false
	for key: Vector2i in _collision.keys():
		if not wanted.has(key) and _distance(key, points) > reach + TILE:
			_collision[key].queue_free()
			_collision.erase(key)
			_base_heights.erase(key)
	# A job nobody needs any more (the tile went out of reach, or was sampled right here) is
	# let go once its worker is done with it.
	for key: Vector2i in _base_jobs.keys():
		if (not wanted.has(key) or _collision.has(key)) and WorkerThreadPool.is_task_completed(int(_base_jobs[key]["task"])):
			WorkerThreadPool.wait_for_task_completion(int(_base_jobs[key]["task"]))
			_base_jobs.erase(key)
	return -1.0 if left else built


func _start_base(key: Vector2i) -> void:
	var result: Array = []
	var task := WorkerThreadPool.add_task(func() -> void: result.append(_base_samples(key)), true, "ground collision")
	_base_jobs[key] = {"task": task, "result": result}


func _take_base(key: Vector2i) -> void:
	var job: Dictionary = _base_jobs[key]
	_base_jobs.erase(key)
	WorkerThreadPool.wait_for_task_completion(int(job["task"]))
	var result: Array = job["result"]
	if not result.is_empty():
		_base_heights[key] = result[0]


## The untouched ground's heights over collision tile `key`. Pure: safe on a worker thread.
func _base_samples(key: Vector2i) -> PackedFloat32Array:
	var n := int(TILE / COLLISION_SPACING) + 1
	var base := PackedFloat32Array()
	base.resize(n * n)
	for j in n:
		for i in n:
			base[j * n + i] = ground_height(key.x * TILE + i * COLLISION_SPACING, key.y * TILE + j * COLLISION_SPACING)
	return base


func _exit_tree() -> void:
	# Tasks read this node's terrain; none may outlive it.
	for job: Dictionary in _base_jobs.values():
		WorkerThreadPool.wait_for_task_completion(int(job["task"]))
	_base_jobs.clear()
	for key: Vector2i in _tile_jobs.keys():
		_drop_tile_job(key)
	_drop_list_job()


## Builds or re-details visible tiles nearest first; true while any is left to do.
func _update_tiles(points: Array[Vector3], budget: float, deadline: int, first: bool) -> bool:
	var tl := Prof.start()
	var listing := false
	if _order_focus != _last_focus:
		if deadline < 0:
			_drop_list_job()
			_apply_list(_last_focus, points, _list(points))
		else:
			listing = _advance_list(points)
	Prof.stop(&"world/voxel_world/tile_list", tl)
	var built := 0.0
	var more := listing
	# The ground under someone with none showing yet (a respawn, a teleport) goes in whatever
	# the budget. Measured from where they are now: the list is from when they last changed
	# tile, or still being made after a teleport.
	var urgent_tiles := {}
	if deadline >= 0:
		urgent_tiles = _tiles_near(points, URGENT_REACH)
		for key: Vector2i in urgent_tiles:
			if _tiles.has(key):
				continue
			if _advance_tile(key, _voxel_for(urgent_tiles[key]), true):
				first = false
			else:
				more = true
	for entry in _tile_order:
		var key := Vector2i(int(entry.y), int(entry.z))
		var voxel := entry.w
		if _tiles.has(key) and not _stale.has(key) and is_equal_approx(_tile_voxel[key], voxel):
			# A job for another detail, from before the points moved back: not needed now.
			if _tile_jobs.has(key):
				_let_go(key)
			continue
		if urgent_tiles.has(key) and not _tiles.has(key):
			continue
		if _spent(built, budget, deadline, first):
			more = true
			break
		if deadline < 0:
			_drop_tile_job(key)
			_replace_tile(key, voxel)
			built += 1.0
		elif _advance_tile(key, voxel, false):
			first = false
		else:
			more = true
	for key: Vector2i in _tile_jobs.keys():
		if not _wanted_tiles.has(key) and not urgent_tiles.has(key):
			_let_go(key)
	return more


## The visible tiles wanted round `points`: [{tile: distance}, the same nearest first as
## Vector4(distance, x, z, voxel size)]. Pure: safe on a worker thread, where it runs while
## streaming (a few hundred tiles took milliseconds of script time).
func _list(points: Array[Vector3]) -> Array:
	var wanted := _tiles_near(points, float(_cfg["load_distance"]))
	var order: Array[Vector4] = []
	for key: Vector2i in wanted:
		var d: float = wanted[key]
		order.append(Vector4(d, key.x, key.y, _voxel_for(d)))
	# Vector4s sort by x first: by distance, natively (a script comparison is far slower).
	order.sort()
	return [wanted, order]


## Lists the tiles on a worker thread when a point has moved to another tile, keeping the old
## list until the new one is ready; true while one is being made.
func _advance_list(points: Array[Vector3]) -> bool:
	if _list_job.is_empty():
		var copy := points.duplicate()
		var result: Array = []
		var task := WorkerThreadPool.add_task(func() -> void: result.append_array(_list(copy)), true, "ground tile list")
		_list_job = {"task": task, "result": result, "focus": _last_focus, "points": copy}
		return true
	if not WorkerThreadPool.is_task_completed(int(_list_job["task"])):
		return true
	var job := _list_job
	_drop_list_job()
	_apply_list(job["focus"], job["points"], job["result"])
	# The points moved on again while it was made: the next call lists them anew.
	return _order_focus != _last_focus


func _drop_list_job() -> void:
	if not _list_job.is_empty():
		WorkerThreadPool.wait_for_task_completion(int(_list_job["task"]))
		_list_job = {}


## Takes `list` (see `_list`) for the focus tiles `focus`, and frees tiles past it.
func _apply_list(focus: Array[Vector2i], points: Array[Vector3], list: Array) -> void:
	_order_focus = focus
	_wanted_tiles = list[0]
	_tile_order = list[1]
	var reach: float = _cfg["load_distance"]
	for key: Vector2i in _tiles.keys():
		if not _wanted_tiles.has(key) and _distance(key, points) > reach + TILE:
			_tiles[key].queue_free()
			_tiles.erase(key)
			_tile_voxel.erase(key)
			_stale.erase(key)


## Moves tile `key`'s build on a step without waiting for any thread: starts its sampling,
## hands the samples to a mesher, or puts the meshed tile in. True once it is in.
func _advance_tile(key: Vector2i, voxel: float, urgent: bool) -> bool:
	var job: Dictionary = _tile_jobs.get(key, {})
	if not job.is_empty() and (int(job["gen"]) != int(_tile_gen.get(key, 0)) or not is_equal_approx(float(job["voxel"]), voxel)):
		# Started before a crater, pad or lane changed the tile, or for another detail.
		if not _let_go(key):
			return false
		job = {}
	if job.is_empty():
		if urgent or _tile_jobs.size() < MAX_JOBS:
			_start_tile(key, voxel)
		return false
	if not bool(job["sampled"]):
		if not WorkerThreadPool.is_task_completed(int(job["task"])):
			return false
		# Finished already: this only lets the pool forget the task.
		WorkerThreadPool.wait_for_task_completion(int(job["task"]))
		job["sampled"] = true
		var inputs: Array = job["result"]
		if inputs.size() < 4:
			_tile_jobs.erase(key)
			return false
		VoxShading.ensure()
		var spacing := _tile_spacing(voxel)
		job["mesh"] = VoxelGround.mesh_start(inputs[0], int(TILE / spacing) + 1, spacing, inputs[1], int(TILE / COLOUR_SPACING) + 1, int(TILE / voxel), voxel, hash(key), _look, inputs[2], inputs[3])
		return false
	var id := int(job["mesh"])
	if not VoxelGround.mesh_ready(id):
		return false
	var tu := Prof.start()
	var arrays := VoxelGround.mesh_take(id)
	_tile_jobs.erase(key)
	_put_tile(key, voxel, arrays)
	Prof.stop(&"world/voxel_world/tile_upload", tu)
	return true


## Drops tile `key`'s job unless its worker is still sampling; true when it is gone.
func _let_go(key: Vector2i) -> bool:
	var job: Dictionary = _tile_jobs.get(key, {})
	if job.is_empty():
		return true
	if not bool(job["sampled"]) and not WorkerThreadPool.is_task_completed(int(job["task"])):
		return false
	_drop_tile_job(key)
	return true


## Samples tile `key` on a worker thread. The craters, pads and lanes it reads change on this
## thread, so it gets its own copies, and the tile's generation to tell whether they still hold.
func _start_tile(key: Vector2i, voxel: float) -> void:
	var result: Array = []
	var spacing := _tile_spacing(voxel)
	var lanes := _own_ways(key)
	var pads: Array = (_pads_in.get(key, []) as Array).duplicate()
	var digs: Array = (_digs_in.get(key, []) as Array).duplicate()
	var work := func() -> void: result.append_array(_tile_inputs(key, spacing, pads, digs, lanes))
	var task := WorkerThreadPool.add_task(work, true, "ground tile")
	_tile_jobs[key] = {"task": task, "result": result, "voxel": voxel, "gen": int(_tile_gen.get(key, 0)), "sampled": false, "mesh": 0}


## Forgets tile `key`'s job, waiting for its worker if it is still sampling (only right-away
## builds and leaving the tree may wait).
func _drop_tile_job(key: Vector2i) -> void:
	if not _tile_jobs.has(key):
		return
	var job: Dictionary = _tile_jobs[key]
	if not bool(job["sampled"]):
		WorkerThreadPool.wait_for_task_completion(int(job["task"]))
	if int(job["mesh"]) != 0:
		VoxelGround.mesh_drop(int(job["mesh"]))
	_tile_jobs.erase(key)


## Tile `key`'s look changed (a crater, a pad, a lane): a job already started for it is out
## of date, and a built one is rebuilt in turn, still showing until then.
func _touch(key: Vector2i) -> void:
	_tile_gen[key] = int(_tile_gen.get(key, 0)) + 1
	if _tiles.has(key):
		_stale[key] = true
	_pending = true


func _voxel_for(distance: float) -> float:
	for lod: Array in _lods:
		if distance <= float(lod[0]):
			return float(lod[1])
	return float((_lods[-1] as Array)[1])


func _focus_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var cam := get_viewport().get_camera_3d() if _visual else null
	if cam != null:
		out.append(cam.global_position)
	else:
		var own: Variant = own_spot_on_client(self)
		if own is Vector3:
			out.append(own)
	var groups: Array[StringName] = [&"terrain_focus"]
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		groups.append_array([&"players", &"enemies", &"vehicles"] as Array[StringName])
	for group in groups:
		for n in get_tree().get_nodes_in_group(group):
			if n is Node3D:
				out.append((n as Node3D).global_position)
	# The spawn stays solid for whoever arrives next.
	out.append(home)
	return out


func _tile_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / TILE), floori(p.z / TILE))


## Tiles within `reach` of any point: {tile: distance to the nearest point}.
func _tiles_near(points: Array[Vector3], reach: float) -> Dictionary:
	var area := heights.extent()
	var out := {}
	for p in points:
		var low := _tile_of(p - Vector3(reach, 0, reach))
		var high := _tile_of(p + Vector3(reach, 0, reach))
		for tx in range(low.x, high.x + 1):
			for tz in range(low.y, high.y + 1):
				var key := Vector2i(tx, tz)
				if not Rect2(tx * TILE, tz * TILE, TILE, TILE).intersects(area):
					continue
				var d := _distance_to(key, p)
				if d <= reach and d < float(out.get(key, INF)):
					out[key] = d
	return out


func _distance(key: Vector2i, points: Array[Vector3]) -> float:
	var best := INF
	for p in points:
		best = minf(best, _distance_to(key, p))
	return best


func _distance_to(key: Vector2i, p: Vector3) -> float:
	var dx := maxf(maxf(key.x * TILE - p.x, p.x - (key.x + 1) * TILE), 0.0)
	var dz := maxf(maxf(key.y * TILE - p.z, p.z - (key.y + 1) * TILE), 0.0)
	return sqrt(dx * dx + dz * dz)


## One point per THIN_GRID metres square: the rest add nothing at tile scale.
func _thin(points: Array[Vector3]) -> Array[Vector3]:
	var seen := {}
	var out: Array[Vector3] = []
	for p in points:
		var cell := Vector2i(floori(p.x / THIN_GRID), floori(p.z / THIN_GRID))
		if not seen.has(cell):
			seen[cell] = true
			out.append(p)
	return out


## Which tile each focus point is in, as one comparable value.
func _focus_key(points: Array[Vector3]) -> Array[Vector2i]:
	var keys: Array[Vector2i] = []
	for p in points:
		keys.append(_tile_of(p))
	keys.sort()
	return keys


## The ground with `pads` and `digs` (tile `key`'s, see `_pads_in`, `_digs_in`) on a grid
## over the tile, `spacing` metres apart. Pure given its own copies: safe on a worker thread.
func _sample(key: Vector2i, spacing: float, pads: Array, digs: Array) -> PackedFloat32Array:
	var n := int(TILE / spacing) + 1
	var out := PackedFloat32Array()
	out.resize(n * n)
	var x0 := key.x * TILE
	var z0 := key.y * TILE
	for j in n:
		for i in n:
			var x := x0 + i * spacing
			var z := z0 + j * spacing
			out[j * n + i] = _dig_into(_pad_into(ground_height(x, z), x, z, pads), x, z, digs)
	return out


## The collision tile's heights: the untouched ground (worked out once per tile) with the
## tile's craters cut in.
func _collision_heights(key: Vector2i) -> PackedFloat32Array:
	var n := int(TILE / COLLISION_SPACING) + 1
	if not _base_heights.has(key):
		_base_heights[key] = _base_samples(key)
	var out := _base_heights[key].duplicate()
	var digs: Array = _digs_in.get(key, [])
	var pads: Array = _pads_in.get(key, [])
	if digs.is_empty() and pads.is_empty():
		return out
	for j in n:
		for i in n:
			var x := key.x * TILE + i * COLLISION_SPACING
			var z := key.y * TILE + j * COLLISION_SPACING
			out[j * n + i] = _dig_into(_pad_into(out[j * n + i], x, z, pads), x, z, digs)
	return out


func _build_collision(key: Vector2i) -> StaticBody3D:
	var n := int(TILE / COLLISION_SPACING) + 1
	var shape := HeightMapShape3D.new()
	shape.map_width = n
	shape.map_depth = n
	shape.map_data = _collision_heights(key)
	var body := StaticBody3D.new()
	body.name = "Ground_%d_%d" % [key.x, key.y]
	body.add_to_group(&"terrain")
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	# A height map is centred on its node.
	body.position = Vector3((key.x + 0.5) * TILE, 0.0, (key.y + 0.5) * TILE)
	add_child(body)
	return body


## Builds tile `key` right here (the spawn before anyone arrives, captures, tests).
func _replace_tile(key: Vector2i, voxel: float) -> void:
	var spacing := _tile_spacing(voxel)
	var ts := Prof.start()
	var inputs := _tile_inputs(key, spacing, _pads_in.get(key, []), _digs_in.get(key, []), _own_ways(key))
	Prof.stop(&"world/voxel_world/tile_sample", ts)
	VoxShading.ensure()
	var tm := Prof.start()
	var arrays := VoxelGround.tile_arrays(inputs[0], int(TILE / spacing) + 1, spacing, inputs[1], int(TILE / COLOUR_SPACING) + 1, int(TILE / voxel), voxel, hash(key), _look, inputs[2], inputs[3])
	Prof.stop(&"world/voxel_world/tile_mesh", tm)
	_put_tile(key, voxel, arrays)


## What tile `key` is meshed from: [heights, colours, ways, dug mask], with `pads`, `digs`
## and `lanes` the tile's own (see `_start_tile`). Pure given its own copies: safe on a
## worker thread.
func _tile_inputs(key: Vector2i, spacing: float, pads: Array, digs: Array, lanes: PackedFloat32Array) -> Array:
	return [_sample(key, spacing, pads, digs), _tile_colours(key, pads, digs), _ways(key, lanes), _dug_mask(key, spacing, digs)]


## Per height sample of tile `key`, 1 where one of `digs` has dug a crater (lanes and strips
## leave its earth unpainted); empty when there are none.
func _dug_mask(key: Vector2i, spacing: float, digs: Array) -> PackedByteArray:
	var mask := PackedByteArray()
	if digs.is_empty():
		return mask
	var n := int(TILE / spacing) + 1
	mask.resize(n * n)
	for j in n:
		for i in n:
			var x := key.x * TILE + i * spacing
			var z := key.y * TILE + j * spacing
			mask[j * n + i] = 1 if _dig_into(0.0, x, z, digs) < -DUG_DEPTH else 0
	return mask


func _tile_spacing(voxel: float) -> float:
	return clampf(voxel * 4.0, 1.0, 8.0)


## Ground colours over tile `key`, dug earth where `pads` and `digs` lower it.
func _tile_colours(key: Vector2i, pads: Array, digs: Array) -> PackedColorArray:
	var cc := int(TILE / COLOUR_SPACING) + 1
	var colours := PackedColorArray()
	colours.resize(cc * cc)
	for j in cc:
		for i in cc:
			colours[j * cc + i] = _colour_at(key.x * TILE + i * COLOUR_SPACING, key.y * TILE + j * COLOUR_SPACING, pads, digs)
	return colours


## Puts a meshed tile in (`arrays` as `VoxelGround.tile_arrays` gives them), in place of any
## earlier one.
func _put_tile(key: Vector2i, voxel: float, arrays: Array) -> void:
	if _tiles.has(key):
		_tiles[key].queue_free()
	var inst := MeshInstance3D.new()
	if not arrays.is_empty():
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, _material)
		inst.mesh = mesh
	inst.set_instance_shader_parameter(&"voxel", voxel)
	inst.position = Vector3(key.x * TILE, 0.0, key.y * TILE)
	add_child(inst)
	_tiles[key] = inst
	_tile_voxel[key] = voxel
	_stale.erase(key)


## The ways this world adds over tile `key`, in world metres: the lanes painted into it and
## the levelled pads (`set_pads_for`, mission buildings), so the ground round a pad tilts
## into it where gentle enough instead of stepping down at its edge.
func _own_ways(key: Vector2i) -> PackedFloat32Array:
	var out: PackedFloat32Array = _lanes_in.get(key, PackedFloat32Array()).duplicate()
	for p: Dictionary in _pads_in.get(key, []):
		# Along the pad's own z (see `_pad_into`), from its `from` end to its level.
		var along := Vector2(float(p["s"]), float(p["c"])) * float(p["hz"])
		var centre := Vector2(float(p["x"]), float(p["z"]))
		var a := centre - along
		var b := centre + along
		out.append_array(PackedFloat32Array([a.x, a.y, float(p["from"]), b.x, b.y, float(p["h"]), float(p["hx"]), WAY_PAD]))
	return out


## The roads, tracks, lanes and pads the ground over tile `key` draws or makes room for (see
## `Earthworks.segments_near`), relative to the tile; `lanes` are this world's own (see
## `_own_ways`) in world metres. Pure: safe on a worker thread.
func _ways(key: Vector2i, lanes: PackedFloat32Array) -> PackedFloat32Array:
	var origin := Vector2(key.x * TILE, key.y * TILE)
	var out := PackedFloat32Array()
	if heights is MapShape and (heights as MapShape).works != null:
		out = (heights as MapShape).works.segments_near(Rect2(origin, Vector2.ONE * TILE), maxf(float(_look.get("band", 0.0)), float(_look.get("pad_band", 0.0))) + 2.0)
	var at := out.size()
	out.append_array(lanes)
	for i in range(at, out.size(), WAY_STRIDE):
		out[i] -= origin.x
		out[i + 1] -= origin.y
		out[i + 3] -= origin.x
		out[i + 4] -= origin.y
	return out


## `owner`'s lanes, replacing its earlier ones: dirt painted into the ground's own voxels
## (a site's yard), with no model of its own and no edge. Each is {from: Vector2, to: Vector2
## (x, z: the middles of its two ends), width, level (its height)}; it ends square at both
## ends. Every client sets the same lanes from the same map; the server draws none.
func set_lanes_for(owner: StringName, lanes: Array) -> void:
	var touched: Dictionary[Vector2i, bool] = {}
	for key: Vector2i in _lanes_in:
		touched[key] = true
	_lane_sets[owner] = lanes
	_lanes_in.clear()
	for set_owner: StringName in _lane_sets:
		for lane: Dictionary in _lane_sets[set_owner]:
			var from: Vector2 = lane["from"]
			var to: Vector2 = lane["to"]
			var half := float(lane["width"]) / 2.0
			var level := float(lane["level"])
			var way := PackedFloat32Array([from.x, from.y, level, to.x, to.y, level, half, WAY_YARD])
			# Its verge reaches a voxel past its edge (at most the coarsest's).
			var reach := Rect2(from, Vector2.ZERO).expand(to).grow(half + _lane_margin)
			for tz in range(floori(reach.position.y / TILE), floori(reach.end.y / TILE) + 1):
				for tx in range(floori(reach.position.x / TILE), floori(reach.end.x / TILE) + 1):
					var key := Vector2i(tx, tz)
					if not _lanes_in.has(key):
						_lanes_in[key] = PackedFloat32Array()
					_lanes_in[key].append_array(way)
					touched[key] = true
	for key: Vector2i in touched:
		_touch(key)


## The lanes painted into tile `key`: way segments in world metres (see `set_lanes_for`).
func lanes_in(key: Vector2i) -> PackedFloat32Array:
	return _lanes_in.get(key, PackedFloat32Array())


## The colour the ground's top gets at x/z (before steep slopes turn it to bare rock).
func ground_colour(x: float, z: float) -> Color:
	var key := _tile_of(Vector3(x, 0.0, z))
	return _colour_at(x, z, _pads_in.get(key, []), _digs_in.get(key, []))


## The colour at x/z, dug earth where `pads` and `digs` (the tile's) lower the ground. Pure
## given its own copies: safe on a worker thread.
func _colour_at(x: float, z: float, pads: Array, digs: Array) -> Color:
	if _biomes == null:
		return GRASS
	var c := GRASS.lerp(STRAW, _biomes.dry(x, z))
	c = c.lerp(LITTER, _biomes.forest(x, z) * 0.8)
	c = c.lerp(SAND, _biomes.sand(x, z))
	c = c.lerp(STONE, _biomes.rock(x, z) * 0.6)
	# A sea cliff is grey rock all through, as the steepest ground is drawn.
	c = c.lerp(ROCK, _biomes.cliff(x, z))
	if not (pads.is_empty() and digs.is_empty()):
		var h := ground_height(x, z)
		if _dig_into(_pad_into(h, x, z, pads), x, z, digs) < h - 0.3:
			c = DIRT
	return c
