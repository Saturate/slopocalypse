class_name MissionBuilding
extends StaticBody3D
## A building in a mission zone: the voxel kit's shed (plank walls, a door, windows, a metal
## roof) with walk-in collision. Built the same on every instance from its layout entry (see
## `MissionLayout`), so nothing about it is sent but that entry. The door is on the local -Z
## side.
##
## It breaks: the walls and roof are cut into segments (about a metre each, two rows up the
## walls), each with its own collision and health. Blasts nearby (drones, mines, charges)
## wear segments down on the server; a broken one loses its collision and is carved out of
## the model with a burst of debris, leaving a hole you can walk or shoot through. The entry's
## `broken` list carries which are gone, so late joiners see the same holes.
##
## Its material decides what bullets do: wood takes a small hole where each one hits and
## enough of them break a piece out; concrete only chips (no hole, next to no damage) and
## needs a blast, a breaching charge or a heavy enough round. Blasts hurt concrete less too.

const DOOR_WIDTH := 1.0
const DOOR_HEIGHT := 2.0
const SLAB := 0.15
const ROOF_THICKNESS := 0.25
const WALL := 0.2
## Voxel size of the mesh: coarse enough to build quickly during a ride.
const VOXEL := 0.15

## The layout entry: `{position, yaw, width, depth, wall_height, windows, paint, seed,
## broken}`.
var spec: Dictionary = {}
## Segment size and health from the missions config (`buildings`).
var segment_size := 1.2
var segment_hp := 100.0
## What its material takes: `{bullet, blast, min_bullet_damage, hole}` (from the missions
## config's `materials`).
var material_cfg: Dictionary = {}

var _visual := DisplayServer.get_name() != "headless"
var _model: VoxelModel
var _mesh: VoxelChunkedMesh
var _shapes: Dictionary[int, CollisionShape3D] = {}
## Server: segment id -> health left.
var _hp: Dictionary[int, float] = {}
var _segments: Array[AABB] = []
## Client: holes were carved this frame; the changed chunks are rebuilt once, next process.
var _remesh := false


func _ready() -> void:
	add_to_group(&"mission_buildings")
	collision_layer = PhysicsLayers.SOLID
	var w := float(spec.get("width", 5.0))
	var d := float(spec.get("depth", 4.0))
	var wh := float(spec.get("wall_height", 2.8))
	_add_shape(-1, AABB(Vector3(-w / 2.0, 0.0, -d / 2.0), Vector3(w, SLAB, d)))
	_segments = segments(w, d, wh, segment_size)
	for i in _segments.size():
		_add_shape(i, _segments[i])
		_hp[i] = segment_hp
	if _visual:
		_model = VoxShed.new().build({
			"seed": int(spec.get("seed", 1)), "paint": int(spec.get("paint", 1)), "width": w,
			"depth": d, "wall_height": wh, "pitch": float(spec.get("pitch", 0.45)), "door": 1,
			"windows": float(spec.get("windows", 2)), "voxel": VOXEL,
			"material": 1 if material() == "concrete" else 0,
		})
		_mesh = VoxelChunkedMesh.new()
		_mesh.name = "Mesh"
		_mesh.model = _model
		add_child(_mesh)
	_remove(spec.get("broken", []), false)
	if _visual:
		_mesh.refresh()


func _add_shape(id: int, box: AABB) -> void:
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = box.size
	shape.shape = b
	shape.position = box.get_center()
	add_child(shape)
	if id >= 0:
		_shapes[id] = shape


## The breakable parts, local: each wall cut along its length into pieces of about `size`
## and into two rows up its height (the front leaves the doorway open, with a lintel over
## it), and the roof as a grid of tiles.
static func segments(w: float, d: float, wh: float, size: float) -> Array[AABB]:
	var out: Array[AABB] = []
	var top := minf(SLAB + DOOR_HEIGHT, wh - 0.2)
	var rows := [[0.0, wh / 2.0], [wh / 2.0, wh]]
	for row: Array in rows:
		var y0 := float(row[0])
		var y1 := float(row[1])
		# Back (+Z), left (-X) and right (+X) walls.
		for piece in _cuts(-w / 2.0, w / 2.0, size):
			out.append(AABB(Vector3(piece.x, y0, d / 2.0 - WALL), Vector3(piece.y - piece.x, y1 - y0, WALL)))
		for piece in _cuts(-d / 2.0, d / 2.0, size):
			out.append(AABB(Vector3(-w / 2.0, y0, piece.x), Vector3(WALL, y1 - y0, piece.y - piece.x)))
			out.append(AABB(Vector3(w / 2.0 - WALL, y0, piece.x), Vector3(WALL, y1 - y0, piece.y - piece.x)))
		# Front (-Z), either side of the door.
		for side: Vector2 in [Vector2(-w / 2.0, -DOOR_WIDTH / 2.0), Vector2(DOOR_WIDTH / 2.0, w / 2.0)]:
			for piece in _cuts(side.x, side.y, size):
				out.append(AABB(Vector3(piece.x, y0, -d / 2.0), Vector3(piece.y - piece.x, y1 - y0, WALL)))
	out.append(AABB(Vector3(-DOOR_WIDTH / 2.0, top, -d / 2.0), Vector3(DOOR_WIDTH, wh - top, WALL)))
	for px in _cuts(-w / 2.0, w / 2.0, size * 1.5):
		for pz in _cuts(-d / 2.0, d / 2.0, size * 1.5):
			out.append(AABB(Vector3(px.x, wh, pz.x), Vector3(px.y - px.x, ROOF_THICKNESS, pz.y - pz.x)))
	return out


## `from`..`to` cut into equal pieces of about `size`, as (start, end) pairs.
static func _cuts(from: float, to: float, size: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var n := maxi(1, int(round((to - from) / size)))
	var step := (to - from) / n
	for i in n:
		out.append(Vector2(from + i * step, from + (i + 1) * step))
	return out


func material() -> String:
	return str(spec.get("material", "wood"))


func segment_count() -> int:
	return _segments.size()


func is_broken(id: int) -> bool:
	return not _shapes.has(id)


## Server: a blast at `centre` (world) with `radius`: segments within `radius * reach` lose
## health (`damage` at the centre, falling off to nothing at the edge of the reach). Returns
## the ids of segments it broke.
func server_blast(centre: Vector3, radius: float, damage: float, reach: float) -> Array[int]:
	var local := global_transform.affine_inverse() * centre
	var far := radius * reach
	var broke: Array[int] = []
	for id: int in _shapes.keys():
		var box := _segments[id]
		var nearest := Vector3(clampf(local.x, box.position.x, box.end.x), clampf(local.y, box.position.y, box.end.y), clampf(local.z, box.position.z, box.end.z))
		var dist := nearest.distance_to(local)
		if dist >= far:
			continue
		_hp[id] = float(_hp.get(id, segment_hp)) - damage * float(material_cfg.get("blast", 1.0)) * (1.0 - dist / far)
		if _hp[id] <= 0.0:
			broke.append(id)
	return broke


## The segment a point on the building (world) is on, or -1.
func segment_at(point: Vector3) -> int:
	var local := global_transform.affine_inverse() * point
	var best := -1
	var best_d := 0.35
	for id: int in _shapes.keys():
		var box := _segments[id]
		var nearest := Vector3(clampf(local.x, box.position.x, box.end.x), clampf(local.y, box.position.y, box.end.y), clampf(local.z, box.position.z, box.end.z))
		var dist := nearest.distance_to(local)
		if dist < best_d:
			best = id
			best_d = dist
	return best


## Server: a bullet hit it at `point` with `damage`. Wood takes it (times its `bullet`
## factor); concrete ignores rounds lighter than `min_bullet_damage`. Returns the segment it
## broke, or -1.
func server_shot(point: Vector3, damage: float) -> int:
	if damage < float(material_cfg.get("min_bullet_damage", 0.0)):
		return -1
	var id := segment_at(point)
	if id < 0:
		return -1
	_hp[id] = float(_hp.get(id, segment_hp)) - damage * float(material_cfg.get("bullet", 1.0))
	return id if _hp[id] <= 0.0 else -1


## Client: where a bullet hit, a hole in wood (and a puff of splinters) or a chip of concrete
## dust; the mesh catches up on the next frame.
func bullet_mark(point: Vector3) -> void:
	if not _visual or _model == null:
		return
	var hole := float(material_cfg.get("hole", 0.0))
	var colour := Color(0.55, 0.55, 0.52) if material() == "concrete" else Color(0.55, 0.42, 0.3)
	if is_inside_tree():
		VoxelDebris.burst(get_parent(), point, (point - global_position).normalized(), colour, &"building_chip")
	if hole <= 0.0:
		return
	var local := global_transform.affine_inverse() * point
	_model.carve_ellipsoid(local, Vector3.ONE * hole)
	_remesh = true


func _process(_delta: float) -> void:
	if not _remesh:
		return
	_remesh = false
	_mesh.refresh()


## Everywhere: takes the segments away (collision, and on clients the voxels with debris).
func break_segments(ids: Array) -> void:
	_remove(ids, true)
	if _visual and _model != null and not ids.is_empty():
		_mesh.refresh()


func _remove(ids: Array, debris: bool) -> void:
	var wh := float(spec.get("wall_height", 2.8))
	var d := float(spec.get("depth", 4.0))
	for v: Variant in ids:
		var id := int(v)
		if not _shapes.has(id):
			continue
		var shape := _shapes[id]
		_shapes.erase(id)
		shape.queue_free()
		if _model == null:
			continue
		var box := _segments[id].grow(VOXEL * 0.5)
		# A roof tile takes the sloping roof above it too.
		if box.position.y >= wh - 0.1:
			box = AABB(box.position, Vector3(box.size.x, d * 0.6 + 0.6, box.size.z))
		_model.carve_box(box.position, box.end)
		if debris and is_inside_tree():
			var centre := _segments[id].get_center()
			# Wall pieces fly out from the building, roof pieces up.
			var out := Vector3.UP if centre.y >= wh - 0.1 else (Vector3(centre.x, 0.0, centre.z).normalized() + Vector3.UP * 0.5)
			VoxelDebris.burst(get_parent(), global_transform * centre, global_transform.basis * out, Color(0.5, 0.42, 0.33), &"building")


## A spot on the floor inside, `along` (0..1 from the door to the back wall) and `side`
## (-1..1 across), in world space.
func inside(along: float, side: float) -> Vector3:
	var w := float(spec.get("width", 5.0))
	var d := float(spec.get("depth", 4.0))
	var local := Vector3(side * (w / 2.0 - WALL - 0.6), SLAB, lerpf(-d / 2.0 + WALL + 0.6, d / 2.0 - WALL - 0.6, along))
	return global_transform * local


## Where guards can stand, in world space, as `[{at, yaw}]` (yaw as a player's: facing
## -Z turned by it): a sentry outside the door looking out, and two inside at the back
## watching the door.
func posts() -> Array:
	var d := float(spec.get("depth", 4.0))
	var door_out := global_transform * Vector3(0.6, SLAB, -d / 2.0 - 1.4)
	# The door is on local -Z, so facing local -Z is both "watching the door" from inside and
	# "looking out" from in front of it.
	var facing := global_rotation.y
	return [
		{"at": door_out, "yaw": facing},
		{"at": inside(0.9, -0.6), "yaw": facing},
		{"at": inside(0.9, 0.6), "yaw": facing},
	]
