class_name VoxelWorld
extends Node3D
## The ground: blocky voxel columns over TerrainHeights, streamed in 32 m tiles around
## whoever needs them, and diggable.
##
## The server builds collision tiles (height maps of the smooth ground, with craters cut in)
## around every player, enemy, vehicle and terrain viewer, so nobody's ground depends on
## anyone else's. Clients build the visible voxel tiles around their camera, finer close by
## and coarser far away. Both apply the same digs from the same replayed events.

const SHADER := "res://modules/world/shaders/voxel_ground.gdshader"
const VOXEL_REQUIRED := {"max_dig_depth": TYPE_FLOAT, "collision_distance": TYPE_FLOAT, "load_distance": TYPE_FLOAT, "lods": TYPE_ARRAY, "builds_per_frame": TYPE_FLOAT}
const TILE := 32.0
## Collision height maps sample the ground every metre.
const COLLISION_SPACING := 1.0
## Ground colours are sampled this far apart and dithered between per voxel.
const COLOUR_SPACING := 4.0
## Steeper than this (rise over run) shows bare rock.
const STEEP_SLOPE := 1.1
const SKIRT := 2.0
## Focus points closer together than this (metres) count as one.
const THIN_GRID := 4.0
## `road_point` keeps this far from the end of the world.
const ROAD_END_MARGIN := 20.0
const GRASS := Color(0.36, 0.5, 0.22)
const LITTER := Color(0.33, 0.29, 0.18)
const STRAW := Color(0.7, 0.61, 0.36)
const STONE := Color(0.5, 0.49, 0.46)
const ROCK := Color(0.45, 0.44, 0.42)
const SOIL := Color(0.42, 0.31, 0.2)
const DIRT := Color(0.38, 0.28, 0.18)
const GRAVEL := Color(0.3, 0.29, 0.27)

## A hole was dug (after clamping), so grass over it can go.
signal dug(center: Vector3, radius: float)

@export_file("*.json") var config_path: String = "res://modules/world/data/world.json"

var heights: TerrainHeights
var max_dig_depth := 3.0

var _biomes: Biomes
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
## Untouched ground heights per collision tile, so a crater only re-applies craters.
var _base_heights: Dictionary[Vector2i, PackedFloat32Array] = {}
var _material: ShaderMaterial
## The focus tiles last time, and whether the build budget ran out then (work left to do).
var _last_focus: Array[Vector2i] = []
var _pending := true


func _ready() -> void:
	var data: Variant = Data.load_json(config_path)
	if not data is Dictionary or not Data.require(config_path, data, TerrainHeights.REQUIRED):
		return
	var world: Dictionary = data
	if not world.has("voxel") or not Data.require(config_path + " voxel", world["voxel"], VOXEL_REQUIRED):
		return
	_cfg = world["voxel"]
	max_dig_depth = _cfg["max_dig_depth"]
	_lods = _cfg["lods"]
	heights = TerrainHeights.new(world)
	if world.get("biomes") is Dictionary:
		_biomes = Biomes.new(world["biomes"], heights.stages)
	# Other modules place things on the ground where no tile is built (the server only builds
	# near players): `ground_height` answers anywhere.
	add_to_group(&"ground")
	if _visual:
		_material = ShaderMaterial.new()
		_material.shader = load(SHADER)
	# The spawn is solid before anyone arrives.
	update_around([Vector3.ZERO], INF)


func _process(_delta: float) -> void:
	var prof := Prof.start()
	_process_tick(_delta)
	Prof.stop(&"world/voxel_world:frame", prof)


func _process_tick(_delta: float) -> void:
	if heights == null:
		return
	update_around(_focus_points(), float(_cfg["builds_per_frame"]))


## A marker that keeps the ground built around it (for cameras in captures and harnesses;
## players, enemies and vehicles are followed already).
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
		if voxels.is_ready_at(Vector3.ZERO):
			break
		await parent.get_tree().physics_frame
	return world


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


## Height of the untouched ground (ignores digging) for placing spawns and scenery.
func ground_height(x: float, z: float) -> float:
	return heights.height_at(x, z) if heights != null else 0.0


## A point on the road `metres` out from the start (past the tunnel portal, if there is
## one), on the untouched ground; the far end of the road if it is shorter than that.
func road_point(metres: float) -> Vector3:
	if heights == null or heights.road == null:
		return Vector3(0.0, 0.0, -metres)
	var start := float(heights.start["portal_z"]) if heights.has_tunnel() else heights.z_max()
	var z := maxf(start - metres, heights.z_min() + ROAD_END_MARGIN)
	var x := heights.road.x_at(z)
	return Vector3(x, heights.height_at(x, z), z)


## The ground as it is now, craters included.
func surface_height(x: float, z: float) -> float:
	return _dig_into(ground_height(x, z), x, z, _digs_in.get(_tile_of(Vector3(x, 0.0, z)), []))


## `h` lowered by any of `digs` over (x, z).
func _dig_into(h: float, x: float, z: float, digs: Array) -> float:
	for d: Vector4 in digs:
		var dx := x - d.x
		var dz := z - d.z
		var r2 := d.w * d.w - dx * dx - dz * dz
		if r2 > 0.0:
			h = minf(h, d.y - sqrt(r2))
	return h


## Carves a sphere out of the ground. Runs on the server and on every client from the same
## replayed event, so all of them dig the same hole. Never deeper than `max_dig_depth` under
## the untouched ground, so stacked explosions can't dig a well.
func server_dig(at: Vector3, radius: float) -> void:
	if heights == null:
		return
	var floor_y := ground_height(at.x, at.z) - max_dig_depth
	var center := Vector3(at.x, maxf(at.y, floor_y + radius), at.z)
	var dig := Vector4(center.x, center.y, center.z, radius)
	var low := _tile_of(center - Vector3(radius, 0, radius))
	var high := _tile_of(center + Vector3(radius, 0, radius))
	for tx in range(low.x, high.x + 1):
		for tz in range(low.y, high.y + 1):
			var key := Vector2i(tx, tz)
			if not _digs_in.has(key):
				_digs_in[key] = []
			_digs_in[key].append(dig)
			if _collision.has(key):
				_collision[key].queue_free()
				_collision[key] = _build_collision(key)
			if _tiles.has(key):
				_replace_tile(key, _tile_voxel[key])
	dug.emit(center, radius)


func update_around(points: Array[Vector3], budget: float) -> void:
	# Many focus points stand close together (a squad, a player in a car): one per few metres
	# is plenty, and fewer points make every distance below cheaper.
	points = _thin(points)
	# Nothing moved to another tile and nothing was left to build last time: nothing to do.
	# This runs every frame, so the common case has to be nearly free.
	var focus := _focus_key(points)
	if focus == _last_focus and not _pending:
		return
	_last_focus = focus
	# Clients build collision too (around their camera): cheap, and the world announces
	# itself only once the spawn is solid, on every machine.
	var built := _update_collision(points, budget)
	_pending = built >= budget
	if _visual:
		_pending = _update_tiles(points, budget - built) or _pending


func _update_collision(points: Array[Vector3], budget: float) -> float:
	var reach: float = _cfg["collision_distance"]
	var wanted := _tiles_near(points, reach)
	var missing: Array = []
	for key: Vector2i in wanted:
		if not _collision.has(key):
			missing.append([wanted[key], key])
	var built := 0.0
	for entry: Array in _nearest_first(missing):
		if built >= budget:
			break
		_collision[entry[1]] = _build_collision(entry[1])
		built += 1.0
	for key: Vector2i in _collision.keys():
		if not wanted.has(key) and _distance(key, points) > reach + TILE:
			_collision[key].queue_free()
			_collision.erase(key)
			_base_heights.erase(key)
	return built


## Builds or re-details visible tiles; true when the budget ran out with work left.
func _update_tiles(points: Array[Vector3], budget: float) -> bool:
	var reach: float = _cfg["load_distance"]
	var wanted := _tiles_near(points, reach)
	var todo: Array = []
	for key: Vector2i in wanted:
		var voxel := _voxel_for(wanted[key])
		if not (_tiles.has(key) and is_equal_approx(_tile_voxel[key], voxel)):
			todo.append([wanted[key], key, voxel])
	var built := 0.0
	for entry: Array in _nearest_first(todo):
		if built >= budget:
			return true
		_replace_tile(entry[1], entry[2])
		built += 1.0
	for key: Vector2i in _tiles.keys():
		if not wanted.has(key) and _distance(key, points) > reach + TILE:
			_tiles[key].queue_free()
			_tiles.erase(key)
			_tile_voxel.erase(key)
	return false


func _voxel_for(distance: float) -> float:
	for lod: Array in _lods:
		if distance <= float(lod[0]):
			return float(lod[1])
	return float((_lods[-1] as Array)[1])


func _focus_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	if _visual:
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			out.append(cam.global_position)
	var groups: Array[StringName] = [&"terrain_focus"]
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		groups.append_array([&"players", &"enemies", &"vehicles"] as Array[StringName])
	for group in groups:
		for n in get_tree().get_nodes_in_group(group):
			if n is Node3D:
				out.append((n as Node3D).global_position)
	# The spawn stays solid for whoever arrives next.
	out.append(Vector3.ZERO)
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


## [[distance, ...], ...] sorted nearest first, distances worked out once beforehand.
func _nearest_first(entries: Array) -> Array:
	entries.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	return entries


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


## The smooth ground (with craters) on a grid over tile `key`, `spacing` metres apart.
func _sample(key: Vector2i, spacing: float) -> PackedFloat32Array:
	var n := int(TILE / spacing) + 1
	var out := PackedFloat32Array()
	out.resize(n * n)
	var x0 := key.x * TILE
	var z0 := key.y * TILE
	for j in n:
		for i in n:
			out[j * n + i] = surface_height(x0 + i * spacing, z0 + j * spacing)
	return out


## The collision tile's heights: the untouched ground (worked out once per tile) with the
## tile's craters cut in.
func _collision_heights(key: Vector2i) -> PackedFloat32Array:
	var n := int(TILE / COLLISION_SPACING) + 1
	if not _base_heights.has(key):
		var base := PackedFloat32Array()
		base.resize(n * n)
		for j in n:
			for i in n:
				base[j * n + i] = ground_height(key.x * TILE + i * COLLISION_SPACING, key.y * TILE + j * COLLISION_SPACING)
		_base_heights[key] = base
	var out := _base_heights[key].duplicate()
	var digs: Array = _digs_in.get(key, [])
	if digs.is_empty():
		return out
	for j in n:
		for i in n:
			out[j * n + i] = _dig_into(out[j * n + i], key.x * TILE + i * COLLISION_SPACING, key.y * TILE + j * COLLISION_SPACING, digs)
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


func _replace_tile(key: Vector2i, voxel: float) -> void:
	if _tiles.has(key):
		_tiles[key].queue_free()
	var spacing := clampf(voxel * 4.0, 1.0, 8.0)
	var cn := int(TILE / spacing) + 1
	var cc := int(TILE / COLOUR_SPACING) + 1
	var colours := PackedColorArray()
	colours.resize(cc * cc)
	for j in cc:
		for i in cc:
			colours[j * cc + i] = ground_colour(key.x * TILE + i * COLOUR_SPACING, key.y * TILE + j * COLOUR_SPACING)
	var arrays := VoxelGround.tile_arrays(_sample(key, spacing), cn, spacing, colours, cc, int(TILE / voxel), voxel, STEEP_SLOPE, ROCK, SOIL, SKIRT, hash(key))
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


## The colour the ground's top gets at x/z (before steep slopes turn it to bare rock).
func ground_colour(x: float, z: float) -> Color:
	# The tunnel's floor under its road shows through potholes: gravel, not grass.
	if heights != null and heights.in_tunnel(x, z, 1.0):
		return GRAVEL
	if _biomes == null:
		return GRASS
	var c := GRASS.lerp(STRAW, _biomes.dry(x, z))
	c = c.lerp(LITTER, _biomes.forest(x, z) * 0.8)
	c = c.lerp(STONE, _biomes.rock(x, z) * 0.6)
	if surface_height(x, z) < ground_height(x, z) - 0.3:
		c = DIRT
	return c
