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
var _digs: Array[Vector4] = []
var _material: ShaderMaterial


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


## The ground as it is now, craters included.
func surface_height(x: float, z: float) -> float:
	var h := ground_height(x, z)
	for d in _digs:
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
	_digs.append(Vector4(center.x, center.y, center.z, radius))
	var low := _tile_of(center - Vector3(radius, 0, radius))
	var high := _tile_of(center + Vector3(radius, 0, radius))
	for tx in range(low.x, high.x + 1):
		for tz in range(low.y, high.y + 1):
			var key := Vector2i(tx, tz)
			if _collision.has(key):
				_collision[key].queue_free()
				_collision[key] = _build_collision(key)
			if _tiles.has(key):
				_replace_tile(key, _tile_voxel[key])
	dug.emit(center, radius)


func update_around(points: Array[Vector3], budget: float) -> void:
	# Clients build collision too (around their camera): cheap, and the world announces
	# itself only once the spawn is solid, on every machine.
	var built := _update_collision(points, budget)
	if _visual:
		_update_tiles(points, budget - built)


func _update_collision(points: Array[Vector3], budget: float) -> float:
	var reach: float = _cfg["collision_distance"]
	var wanted := _tiles_near(points, reach)
	var built := 0.0
	for key: Vector2i in _sorted_by_distance(wanted.keys(), points):
		if _collision.has(key):
			continue
		if built >= budget:
			break
		_collision[key] = _build_collision(key)
		built += 1.0
	for key: Vector2i in _collision.keys():
		if not wanted.has(key) and _distance(key, points) > reach + TILE:
			_collision[key].queue_free()
			_collision.erase(key)
	return built


func _update_tiles(points: Array[Vector3], budget: float) -> void:
	var reach: float = _cfg["load_distance"]
	var wanted := _tiles_near(points, reach)
	var built := 0.0
	for key: Vector2i in _sorted_by_distance(wanted.keys(), points):
		if built >= budget:
			break
		var voxel := _voxel_for(_distance(key, points))
		if _tiles.has(key) and is_equal_approx(_tile_voxel[key], voxel):
			continue
		_replace_tile(key, voxel)
		built += 1.0
	for key: Vector2i in _tiles.keys():
		if not wanted.has(key) and _distance(key, points) > reach + TILE:
			_tiles[key].queue_free()
			_tiles.erase(key)
			_tile_voxel.erase(key)


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
				if _distance(key, [p]) <= reach:
					out[key] = true
	return out


func _distance(key: Vector2i, points: Array[Vector3]) -> float:
	var best := INF
	for p in points:
		var dx := maxf(maxf(key.x * TILE - p.x, p.x - (key.x + 1) * TILE), 0.0)
		var dz := maxf(maxf(key.y * TILE - p.z, p.z - (key.y + 1) * TILE), 0.0)
		best = minf(best, sqrt(dx * dx + dz * dz))
	return best


func _sorted_by_distance(keys: Array, points: Array[Vector3]) -> Array:
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return _distance(a, points) < _distance(b, points))
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


func _build_collision(key: Vector2i) -> StaticBody3D:
	var n := int(TILE / COLLISION_SPACING) + 1
	var shape := HeightMapShape3D.new()
	shape.map_width = n
	shape.map_depth = n
	shape.map_data = _sample(key, COLLISION_SPACING)
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
