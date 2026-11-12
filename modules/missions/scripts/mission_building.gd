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
## Weight counts: every piece weighs what its voxels do (each material's `density`) and can
## carry so many times its own weight (its main material's `strength`). After a break the
## server passes the weight of everything standing down to the ground, and a piece carrying
## more than it can gives way, so a house isn't held up by one corner piece.
##
## Pieces nothing holds up any more fall (see `BuildingSupport`): the server takes them
## away with the pieces that broke and hurts whoever is under them when they land; clients
## drop their voxels as one piece per connected group, then break it into debris.
##
## Materials decide what hits do (see `VoxMaterials`). The voxel a round strikes decides what
## it leaves: a hole in wood or sheet metal, a chip off brick or concrete, debris in that
## voxel's colour. How much a piece of wall suffers comes from that piece's main material,
## so a wooden window frame in a concrete wall doesn't make the concrete easy to break: wood
## breaks to rounds, brick and concrete only to blasts, charges or rounds heavy enough. Glass
## panes take no structural damage: they break on their own. Each pane (a connected patch of
## one glass material) counts its hits on the server and goes whole once it has taken its
## material's `hits_to_break` (window and tempered glass on the first, laminated after six,
## security glass after twelve), or at once in a blast; panes that crack get a lighter mark
## where each round struck. Broken panes travel in the entry's `panes_broken`.
##
## Bricks come out one at a time: a material with `pop_damage` (brick) is laid as blocks
## walled in by another (mortar), and once the rounds into one block add up to that much damage
## it pops out, leaving a brick-shaped hole. The server counts it per brick and names a point
## inside it; every instance finds the same brick from that point, and the entry's `knocked`
## carries them to late joiners. Mortar sticks bricks together: each brick touching one that
## comes out may come too (`stick_chance`, half as likely a step further), rolled on the server
## so everyone loses the same cluster, and mortar left touching no brick crumbles away. Rounds
## into a joint wear the bricks either side of it. A wall piece that has lost most of its
## bricks gives way.
##
## Every instance builds the voxel model, the server too (without a mesh), so a hit looks up
## the same voxels everywhere.

const DOOR_WIDTH := 1.0
const DOOR_HEIGHT := 2.0
const SLAB := 0.15
const ROOF_THICKNESS := 0.25
const WALL := 0.2
## Voxel size of the mesh: coarse enough to build quickly during a ride. Brick buildings
## use a finer one, so each brick and its mortar joint show (see `VoxShed`).
const VOXEL := 0.15
const BRICK_VOXEL := 0.075
## How far into a wall a hit looks for the voxel it struck, metres.
const STRIKE_DEPTH := 0.6
## A crack mark's radius on glass, metres.
const CRACK_RADIUS := 0.12
## The most cells one brick can have; a bigger patch of brick is a wall, not a brick.
const BRICK_CAP := 400
## A round into a joint wears each brick beside it by this share of its damage.
const JOINT_SHARE := 0.5
## A wall piece left with less than this share of its bricks gives way.
const BRICK_HOLD := 0.4

## The layout entry: `{position, yaw, width, depth, wall_height, windows, paint, seed,
## broken}`.
var spec: Dictionary = {}
## Segment size and health from the missions config (`buildings`).
var segment_size := 1.2
var segment_hp := 100.0
## Collapse: roof pieces further than this many pieces from a standing wall fall, and how long
## a falling piece takes to land (from the missions config's `buildings`).
var max_span := 2
var fall_seconds := 0.6
## The walls' entry in the voxkit materials file (`VoxMaterials`), set from `spec.material`
## when nothing sets it first: the rules for a piece with no voxels of its own.
var material_cfg: Dictionary = {}

var _visual := DisplayServer.get_name() != "headless"
## This building's voxel size (`BRICK_VOXEL` for brick, else `VOXEL`).
var voxel := VOXEL
var _model: VoxelModel
var _mesh: VoxelChunkedMesh
var _shapes: Dictionary[int, CollisionShape3D] = {}
## Server: segment id -> health left.
var _hp: Dictionary[int, float] = {}
var _segments: Array[AABB] = []
## Segment id -> its main material's index (0: none, use `material_cfg`).
var _segment_material := PackedByteArray()
## The panes, numbered alike everywhere: `{box: AABB (local), material: int}`.
var _panes: Array[Dictionary] = []
## Server: pane index -> hits taken.
var _pane_hits: Dictionary[int, int] = {}
var _panes_gone: Dictionary[int, bool] = {}
## Server: damage taken per brick, keyed by the brick's box.
var _brick_wear: Dictionary[String, float] = {}
## Server: the dice for which neighbours a knocked-out brick drags along.
var _stick_rng := RandomNumberGenerator.new()
## Segment id -> how many brick cells it started with (only pieces that have bricks).
var _bricks_at_start: Dictionary[int, int] = {}
## Per segment: its weight (kg, from its voxels) and how much it can carry (kg).
var _mass := PackedFloat32Array()
var _strength := PackedFloat32Array()
## The support graph (built on first use): connected segment pairs, roof flags and the
## segments standing on the slab.
var _edges := PackedInt32Array()
var _roof := PackedByteArray()
var _anchors := PackedInt32Array()
## Client: holes were carved this frame; the changed chunks are rebuilt once, next process.
var _remesh := false
## Colour of the group falling now, for its landing debris.
var _fall_colour := Color(0.5, 0.42, 0.33)


func _ready() -> void:
	add_to_group(&"mission_buildings")
	# Its hits and breaks send their own sounds (`missions.surface_*`); see `_sound`.
	set_meta(&"surface_sounds", true)
	if material_cfg.is_empty():
		material_cfg = VoxMaterials.named(material())
	voxel = BRICK_VOXEL if material() == "brick" else VOXEL
	collision_layer = PhysicsLayers.SOLID
	var w := float(spec.get("width", 5.0))
	var d := float(spec.get("depth", 4.0))
	var wh := float(spec.get("wall_height", 2.8))
	_add_shape(-1, AABB(Vector3(-w / 2.0, 0.0, -d / 2.0), Vector3(w, SLAB, d)))
	_segments = segments(w, d, wh, segment_size)
	for i in _segments.size():
		_add_shape(i, _segments[i])
		_hp[i] = segment_hp
	_model = VoxShed.new().build({
		"seed": int(spec.get("seed", 1)), "paint": int(spec.get("paint", 1)), "width": w,
		"depth": d, "wall_height": wh, "pitch": float(spec.get("pitch", 0.45)), "door": 1,
		"windows": float(spec.get("windows", 2)), "voxel": voxel,
		"material": maxi(0, VoxShed.WALL_MATERIALS.find(material())),
		"glass": maxi(0, VoxShed.GLASS_TYPES.find(str(spec.get("glass", "window_glass")))),
	})
	for i in VoxMaterials.all().size():
		if bool(VoxMaterials.at(i).get("breaks_whole", false)):
			for box: AABB in _model.components(i):
				_panes.append({"box": box, "material": i})
	_segment_material.resize(_segments.size())
	var brick := VoxMaterials.index_of("brick")
	for i in _segments.size():
		var box := _carve_box(i)
		_segment_material[i] = _model.dominant_material(box.position, box.end)
		var bricks := _model.count_material(box.position, box.end, brick)
		if bricks > 0:
			_bricks_at_start[i] = bricks
	_weigh()
	if _visual:
		# Glass is drawn see-through.
		var glass := PackedInt32Array()
		for i in VoxMaterials.all().size():
			if bool(VoxMaterials.at(i).get("breaks_whole", false)):
				glass.append(i)
		_model.set_clear_materials(glass)
		_mesh = VoxelChunkedMesh.new()
		_mesh.layered = true
		_mesh.name = "Mesh"
		_mesh.model = _model
		add_child(_mesh)
	_remove(spec.get("broken", []), false)
	break_panes(spec.get("panes_broken", []), false)
	knock_out(spec.get("knocked", []), false)
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


## The material of the voxel at a hit `point` (world) on a face with `normal`: half a voxel
## into the surface.
func material_at(point: Vector3, normal: Vector3) -> String:
	var local := global_transform.affine_inverse() * (point - normal.normalized() * voxel * 0.5)
	return str(VoxMaterials.at(_model.material_at(local))["name"])


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
		_hp[id] = float(_hp.get(id, segment_hp)) - damage * float(segment_rules(id).get("blast", 1.0)) * (1.0 - dist / far)
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


## The rules of segment `id`'s main material.
func segment_rules(id: int) -> Dictionary:
	var m := int(_segment_material[id]) if id >= 0 and id < _segment_material.size() else 0
	return VoxMaterials.at(m) if m > 0 else material_cfg


## The voxel a round travelling along `direction` struck at `point` (world): the first filled
## one within `STRIKE_DEPTH` into the wall, as a local position, or `Vector3.INF` (it went
## into a hole). With no direction it looks in towards the middle of the building.
func struck_voxel(point: Vector3, direction: Vector3) -> Vector3:
	var to_local := global_transform.affine_inverse()
	var at := to_local * point
	var dir := (to_local.basis * direction).normalized() if direction.length_squared() > 0.0 else -Vector3(at.x, 0.0, at.z).normalized()
	var step := voxel * 0.5
	var p := at - dir * step
	var travelled := -step
	while travelled <= STRIKE_DEPTH:
		if _model.material_at(p) != 0:
			return p
		p += dir * step
		travelled += step
	return Vector3.INF


## The rules of the voxel struck at `point` along `direction` (the walls' when nothing is
## there to strike).
func struck_rules(point: Vector3, direction: Vector3) -> Dictionary:
	var v := struck_voxel(point, direction)
	return VoxMaterials.at(_model.material_at(v)) if v != Vector3.INF else material_cfg


func pane_count() -> int:
	return _panes.size()


func is_pane_broken(index: int) -> bool:
	return _panes_gone.has(index)


## The pane a round travelling along `direction` struck at `point`, or -1 (not glass that
## breaks whole).
func pane_at(point: Vector3, direction: Vector3) -> int:
	var v := struck_voxel(point, direction)
	if v == Vector3.INF:
		return -1
	var m := _model.material_at(v)
	for i in _panes.size():
		var pane: Dictionary = _panes[i]
		if int(pane["material"]) == m and not _panes_gone.has(i) and (pane["box"] as AABB).grow(voxel * 0.5).has_point(v):
			return i
	return -1


## Server: a round struck at `point` along `direction`. If it was a pane, it counts the hit
## (rounds too light to go through still wear it); returns the pane's index once it breaks,
## else -1.
func server_pane_hit(point: Vector3, direction: Vector3) -> int:
	var i := pane_at(point, direction)
	if i < 0:
		return -1
	_pane_hits[i] = int(_pane_hits.get(i, 0)) + 1
	var rules := VoxMaterials.at(int(_panes[i]["material"]))
	return i if _pane_hits[i] >= maxi(1, int(rules.get("hits_to_break", 1))) else -1


## Server: the panes a blast at `centre` (world) reaches: every one within `radius * reach`
## goes at once.
func server_blast_panes(centre: Vector3, radius: float, reach: float) -> Array[int]:
	var local := global_transform.affine_inverse() * centre
	var out: Array[int] = []
	for i in _panes.size():
		if _panes_gone.has(i):
			continue
		var box: AABB = _panes[i]["box"]
		var nearest := Vector3(clampf(local.x, box.position.x, box.end.x), clampf(local.y, box.position.y, box.end.y), clampf(local.z, box.position.z, box.end.z))
		if nearest.distance_to(local) < radius * reach:
			out.append(i)
	return out


## Everywhere: the panes go, leaving their frames; on clients with shards (big ones for
## window glass, a spray of small ones for tempered) and a break sound.
func break_panes(indices: Array, debris: bool) -> void:
	for v: Variant in indices:
		var i := int(v)
		if i < 0 or i >= _panes.size() or _panes_gone.has(i):
			continue
		_panes_gone[i] = true
		var pane: Dictionary = _panes[i]
		var box: AABB = pane["box"]
		var rules := VoxMaterials.at(int(pane["material"]))
		var colour := _model.colour_at(box.get_center())
		_model.carve_material_box(box.position - Vector3.ONE * voxel * 0.1, box.end + Vector3.ONE * voxel * 0.1, int(pane["material"]))
		if debris and _visual and is_inside_tree():
			var at := global_transform * box.get_center()
			var source := &"glass_bits" if str(rules.get("name", "")) == "tempered_glass" else &"glass_shards"
			var out := (global_transform.basis * Vector3(box.get_center().x, 0.0, box.get_center().z)).normalized()
			VoxelDebris.burst(get_parent(), at, out + Vector3.DOWN * 0.3, colour if colour.a > 0.0 else Color(0.2, 0.27, 0.32), source)
			_sound(&"missions.surface_broke", at, str(rules.get("name", "")), 1)
	if _visual and not indices.is_empty():
		_remesh = true


## Server: a round with `damage` struck at `point` along `direction`. If it struck a block
## that pops out (a brick), it adds to that brick's wear, or, in a joint, to the bricks either
## side. Returns points inside the bricks to knock out (local): any that reached their
## material's `pop_damage`, and the neighbours they drag along; empty for none.
func server_brick_hit(point: Vector3, direction: Vector3, damage: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var v := struck_voxel(point, direction)
	if v == Vector3.INF:
		return out
	var m := _model.material_at(v)
	var targets: Array[Vector3] = []
	if float(VoxMaterials.at(m).get("pop_damage", 0.0)) > 0.0:
		targets.append(v)
	else:
		# A joint: the bricks touching this spot share the round.
		for p in _brick_points_near(v, voxel * 1.5):
			targets.append(p)
	for t in targets:
		var tm := _model.material_at(t)
		var pop := float(VoxMaterials.at(tm).get("pop_damage", 0.0))
		var box := _model.component_at(t, tm, BRICK_CAP)
		if pop <= 0.0 or box.size == Vector3.ZERO:
			continue
		var key := str(box.position)
		# Straight into a brick it takes the round; in a joint, each brick beside it half.
		var share := 1.0 if targets.size() == 1 and t == v else JOINT_SHARE
		_brick_wear[key] = float(_brick_wear.get(key, 0.0)) + damage * share
		if _brick_wear[key] >= pop:
			_brick_wear.erase(key)
			out.append(t)
	if not out.is_empty():
		out.append_array(_dragged_along(out))
	return out


## Points inside the bricks touching `at` (local) within `reach`, one per brick.
func _brick_points_near(at: Vector3, reach: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var seen: Dictionary[String, bool] = {}
	for d: Vector3 in [Vector3.LEFT, Vector3.RIGHT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]:
		var p := at + d * reach
		var m := _model.material_at(p)
		if m == 0 or float(VoxMaterials.at(m).get("pop_damage", 0.0)) <= 0.0:
			continue
		var box := _model.component_at(p, m, BRICK_CAP)
		if box.size == Vector3.ZERO or seen.has(str(box.position)):
			continue
		seen[str(box.position)] = true
		out.append(p)
	return out


## Server: the bricks the knocked-out ones drag along: each brick touching one across a joint
## comes with its material's `stick_chance`, and those with half that again, two steps at
## most. Points inside them (local).
func _dragged_along(knocked: Array[Vector3]) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var gone: Dictionary[String, bool] = {}
	var ring := knocked.duplicate()
	for p in knocked:
		gone[str(_model.component_at(p, _model.material_at(p), BRICK_CAP).position)] = true
	var share := 1.0
	for step in 2:
		var next: Array[Vector3] = []
		for p in ring:
			var m := _model.material_at(p)
			var box := _model.component_at(p, m, BRICK_CAP)
			if box.size == Vector3.ZERO:
				continue
			var chance := float(VoxMaterials.at(m).get("stick_chance", 0.0)) * share
			for q in _neighbour_bricks(box, m):
				var key := str(_model.component_at(q, m, BRICK_CAP).position)
				if gone.has(key):
					continue
				gone[key] = true
				if _stick_rng.randf() < chance:
					next.append(q)
		out.append_array(next)
		ring = next
		share *= 0.5
	return out


## A point inside each brick of material `m` across a joint from `box` (local).
func _neighbour_bricks(box: AABB, m: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var seen: Dictionary[String, bool] = {str(box.position): true}
	var reach := voxel * 1.5
	var c := box.get_center()
	var probes: Array[Vector3] = []
	for a in 3:
		for side: float in [-1.0, 1.0]:
			var face := c
			face[a] = (box.end[a] + reach) if side > 0.0 else (box.position[a] - reach)
			# A few points along the face, so a brick offset by half a length is found too.
			var b := (a + 1) % 3
			for k: float in [-0.35, 0.0, 0.35]:
				var p := face
				p[b] = c[b] + k * box.size[b]
				probes.append(p)
	for p in probes:
		if _model.material_at(p) != m:
			continue
		var other := _model.component_at(p, m, BRICK_CAP)
		if other.size == Vector3.ZERO or seen.has(str(other.position)):
			continue
		seen[str(other.position)] = true
		out.append(p)
	return out


## Everywhere: the bricks holding these points (local) come out, with a little debris and a
## crumble on clients.
func knock_out(points: Array, debris: bool) -> void:
	for p: Variant in points:
		var at: Vector3 = p
		var m := _model.material_at(at)
		if m == 0:
			continue
		var box := _model.component_at(at, m, BRICK_CAP)
		if box.size == Vector3.ZERO:
			continue
		var colour := _model.colour_at(at)
		_model.carve_material_box(box.position - Vector3.ONE * voxel * 0.1, box.end + Vector3.ONE * voxel * 0.1, m)
		_crumble_loose(box.grow(voxel), m)
		if debris and _visual and is_inside_tree():
			var world := global_transform * box.get_center()
			var out := (global_transform.basis * Vector3(box.get_center().x, 0.0, box.get_center().z)).normalized()
			VoxelDebris.burst(get_parent(), world, out, colour if colour.a > 0.0 else Color(0.55, 0.27, 0.2), &"brick")
			_sound(&"missions.surface_broke", world, str(VoxMaterials.at(m).get("name", "")), 1)
	if _visual and not points.is_empty():
		_remesh = true


## Everywhere: in `box` (local), joint material left touching no brick of material `m` (no
## brick on any face) crumbles away, so a hole opens clean instead of leaving a mortar grid.
func _crumble_loose(box: AABB, m: int) -> void:
	var half := voxel * 0.5
	var x := box.position.x + half
	while x < box.end.x:
		var y := box.position.y + half
		while y < box.end.y:
			var z := box.position.z + half
			while z < box.end.z:
				var p := Vector3(x, y, z)
				var here := _model.material_at(p)
				if here != 0 and here != m and float(VoxMaterials.at(here).get("pop_damage", 0.0)) <= 0.0 and str(VoxMaterials.at(here).get("name", "")) == "mortar":
					var held := false
					for d: Vector3 in [Vector3.LEFT, Vector3.RIGHT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]:
						if _model.material_at(p + d * voxel) == m:
							held = true
							break
					if not held:
						_model.carve_material_box(p - Vector3.ONE * half * 0.9, p + Vector3.ONE * half * 0.9, here)
				z += voxel
			y += voxel
		x += voxel


## Server: the standing wall pieces that have lost too many bricks to stand.
func server_weakened() -> Array[int]:
	var brick := VoxMaterials.index_of("brick")
	var out: Array[int] = []
	for id: int in _bricks_at_start:
		if not _shapes.has(id):
			continue
		var box := _carve_box(id)
		if float(_model.count_material(box.position, box.end, brick)) < float(_bricks_at_start[id]) * BRICK_HOLD:
			out.append(id)
	return out


## Server, for the weapons' trace: whether a round travelling along `direction` that hit
## at `point` with `damage` goes on through. `{exit, scale}` lets it carry on from `exit`
## (world, just past the wall) with its damage times `scale`; `{}` stops it. Through a hole
## already made it carries on whole. Through the wall when the struck material passes
## rounds (`pass` > 0), the round is heavy enough (`min_bullet_damage`), and the wall along
## its path is no thicker than that material allows (`thickness_max`); anything on the way
## that doesn't pass rounds stops it.
func bullet_exit(point: Vector3, direction: Vector3, damage: float) -> Dictionary:
	var to_local := global_transform.affine_inverse()
	var dir := (to_local.basis * direction).normalized()
	var v := struck_voxel(point, direction)
	if v == Vector3.INF:
		return {"exit": point + direction.normalized() * (STRIKE_DEPTH + voxel), "scale": 1.0}
	var rules := VoxMaterials.at(_model.material_at(v))
	var pass_share := float(rules.get("pass", 0.0))
	if pass_share <= 0.0 or damage < float(rules.get("min_bullet_damage", 0.0)):
		return {}
	var step := voxel * 0.25
	var thickness := 0.0
	var p := v
	var limit := float(rules.get("thickness_max", 0.0))
	while true:
		var m := _model.material_at(p)
		if m == 0:
			break
		if float(VoxMaterials.at(m).get("pass", 0.0)) <= 0.0:
			return {}
		thickness += step
		# Nothing is thinner than a voxel here, so a thin pane or sheet counts as one.
		if thickness > maxf(limit, voxel) + step:
			return {}
		p += dir * step
	return {"exit": global_transform * (p + dir * step), "scale": pass_share}


## Server: a bullet travelling along `direction` hit it at `point` with `damage`. The piece
## it hit takes it by the piece's main material: times its `bullet` factor, and not at all
## from rounds lighter than its `min_bullet_damage`. A glass pane takes no structural damage.
## Returns the segment it broke, or -1.
func server_shot(point: Vector3, damage: float, direction := Vector3.ZERO) -> int:
	var t := Prof.start()
	var broke := _shot(point, damage, direction)
	Prof.stop(&"missions/building:shot", t)
	return broke


func _shot(point: Vector3, damage: float, direction: Vector3) -> int:
	var id := segment_at(point)
	if id < 0:
		return -1
	if bool(struck_rules(point, direction).get("breaks_whole", false)):
		return -1
	var rules := segment_rules(id)
	if damage < float(rules.get("min_bullet_damage", 0.0)):
		return -1
	_hp[id] = float(_hp.get(id, segment_hp)) - damage * float(rules.get("bullet", 1.0))
	return id if _hp[id] <= 0.0 else -1


## Everywhere: where a bullet travelling along `direction` hit, the voxel it struck takes it:
## a hole if its material takes holes, and on clients a puff of debris in that voxel's
## colour. Carved on the server too, so later hits find the same voxels. The mesh catches up
## on the next frame.
func bullet_mark(point: Vector3, direction := Vector3.ZERO) -> void:
	var t := Prof.start()
	_mark(point, direction)
	Prof.stop(&"missions/building:mark", t)


func _mark(point: Vector3, direction: Vector3) -> void:
	var v := struck_voxel(point, direction)
	if v == Vector3.INF:
		return
	var rules := VoxMaterials.at(_model.material_at(v))
	_sound(&"missions.surface_hit", point, str(rules.get("name", "")), 1)
	if _visual and is_inside_tree():
		# Something comes off (a hole): a few small chips; nothing does: a puff of dust.
		var colour := _model.colour_at(v)
		var out := -direction.normalized() if direction.length_squared() > 0.0 else (point - global_position).normalized()
		var source := &"building_chip" if float(rules.get("hole", 0.0)) > 0.0 else &"dust"
		VoxelDebris.burst(get_parent(), point, out, (colour if colour.a > 0.0 else Color(0.55, 0.5, 0.45)).lightened(0.15 if source == &"dust" else 0.0), source)
	if bool(rules.get("crack", false)):
		# A lighter star where it struck; only the glass, not its frame.
		var glass := _model.colour_at(v)
		_model.recolour_ellipsoid(v, Vector3.ONE * CRACK_RADIUS, glass.lerp(Color(0.92, 0.94, 0.95), 0.6), _model.material_at(v))
		_remesh = _visual
	var hole := float(rules.get("hole", 0.0))
	if hole <= 0.0:
		return
	_model.carve_ellipsoid(v, Vector3.ONE * hole)
	_remesh = _visual


func _process(_delta: float) -> void:
	if not _remesh:
		return
	_remesh = false
	_mesh.refresh()


## Everywhere: takes the segments away (collision, and on clients the voxels with debris).
## `fallen` ones lost their support: on clients they drop as whole pieces first.
func break_segments(ids: Array, fallen: Array = []) -> void:
	var t := Prof.start()
	_break(ids, fallen)
	Prof.stop(&"missions/building:break", t)


func _break(ids: Array, fallen: Array) -> void:
	_sound_breaks(ids)
	_remove(ids, true)
	if _visual and _model != null and is_inside_tree():
		for group in _groups(fallen):
			_drop(group)
	_remove(fallen, false)
	if _visual and _model != null and not (ids.is_empty() and fallen.is_empty()):
		_mesh.refresh()


## Server: once `newly` break, the standing segments nothing holds up any more.
func server_unsupported(newly: Array[int]) -> Array[int]:
	if _roof.is_empty():
		_build_graph()
	var broken := PackedInt32Array(newly)
	for id in _segments.size():
		if not _shapes.has(id) and not newly.has(id):
			broken.append(id)
	var out: Array[int] = []
	for id in BuildingSupport.unsupported(_roof, _edges, _anchors, broken, max_span):
		out.append(id)
	return out


## Server: once `newly` break, the standing segments carrying more than they can.
func server_overloaded(newly: Array[int]) -> Array[int]:
	if _roof.is_empty():
		_build_graph()
	var broken := PackedInt32Array(newly)
	for id in _segments.size():
		if not _shapes.has(id) and not newly.has(id):
			broken.append(id)
	var out: Array[int] = []
	for id in BuildingSupport.overloaded(_edges, _anchors, broken, _mass, _strength):
		out.append(id)
	return out


## Each segment's weight from its voxels (count of each material times its density), what it
## can carry (each material's weight there times its strength, added up), and its main
## material: the most common one that isn't a joint (mortar never is a brick wall's).
func _weigh() -> void:
	_mass.resize(_segments.size())
	_strength.resize(_segments.size())
	var cell := voxel * voxel * voxel
	var all := VoxMaterials.all()
	for i in _segments.size():
		var box := _carve_box(i)
		var kg := 0.0
		var carries := 0.0
		var main := 0
		var main_count := 0
		for m in range(1, all.size()):
			var n := _model.count_material(box.position, box.end, m)
			if n <= 0:
				continue
			var part := n * cell * float(all[m].get("density", 1000.0))
			kg += part
			carries += part * float(all[m].get("strength", 10.0))
			if not bool(all[m].get("joint", false)) and n > main_count:
				main = m
				main_count = n
		_mass[i] = kg
		_strength[i] = carries
		if main > 0:
			_segment_material[i] = main


func segment_mass(id: int) -> float:
	return _mass[id] if id >= 0 and id < _mass.size() else 0.0


## Server: fallen segments land: everyone under them takes `damage` once.
func server_crush(fallen: Array[int], damage: float) -> void:
	var to_local := global_transform.affine_inverse()
	for group: StringName in [&"players", &"enemies", &"vehicles"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var body := node as Node3D
			if body == null:
				continue
			var at := to_local * body.global_position
			for id in fallen:
				var box := _segments[id]
				if at.x >= box.position.x and at.x <= box.end.x and at.z >= box.position.z and at.z <= box.end.z and at.y < box.position.y:
					var health := HealthComponent.find_on(body)
					if health != null:
						health.server_apply_damage(damage, self)
					break


## Segments connect where their boxes touch (a shared face or edge); anchors stand on the slab.
func _build_graph() -> void:
	var wh := float(spec.get("wall_height", 2.8))
	_roof.resize(_segments.size())
	for i in _segments.size():
		var box := _segments[i]
		_roof[i] = 1 if box.position.y >= wh - 0.01 else 0
		if _roof[i] == 0 and box.position.y <= 0.01:
			_anchors.append(i)
		for j in range(i + 1, _segments.size()):
			if box.grow(0.01).intersects(_segments[j].grow(0.01)):
				_edges.append(i)
				_edges.append(j)


## `ids` split into groups connected through each other.
func _groups(ids: Array) -> Array[Array]:
	if _roof.is_empty():
		_build_graph()
	var left: Dictionary[int, bool] = {}
	for v: Variant in ids:
		left[int(v)] = true
	var out: Array[Array] = []
	while not left.is_empty():
		var start: int = left.keys()[0]
		left.erase(start)
		var group: Array[int] = [start]
		var k := 0
		while k < group.size():
			var at := group[k]
			k += 1
			for e in range(0, _edges.size(), 2):
				var other := -1
				if _edges[e] == at:
					other = _edges[e + 1]
				elif _edges[e + 1] == at:
					other = _edges[e]
				if other >= 0 and left.has(other):
					left.erase(other)
					group.append(other)
		out.append(group)
	return out


## Client: the voxels of a connected group of fallen segments drop as one piece, land after
## `fall_seconds`, then burst into debris.
func _drop(group: Array) -> void:
	var piece := Node3D.new()
	piece.name = "Falling"
	add_child(piece)
	var lowest := INF
	var centres: Array[Vector3] = []
	for v: Variant in group:
		var box := _carve_box(int(v))
		var copy: Dictionary = _model.copy_box(box.position, box.end)
		if copy.is_empty():
			continue
		if centres.is_empty():
			_fall_colour = _colour_of(int(v))
		var part := MeshInstance3D.new()
		part.mesh = VoxGenerator.to_mesh(copy["model"])
		part.position = copy["offset"]
		piece.add_child(part)
		lowest = minf(lowest, _segments[int(v)].position.y)
		centres.append(_segments[int(v)].get_center())
	if centres.is_empty():
		piece.queue_free()
		return
	var drop := maxf(lowest - SLAB, 0.0)
	var colour := _fall_colour
	var tween := piece.create_tween()
	tween.tween_property(piece, "position:y", -drop, fall_seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		if is_inside_tree() and not centres.is_empty():
			_sound(&"missions.surface_landed", global_transform * (centres[0] + Vector3.DOWN * drop), "", centres.size())
		if is_inside_tree():
			for c in centres:
				var at := global_transform * (c + Vector3.DOWN * drop)
				VoxelDebris.burst(get_parent(), at, Vector3.UP, colour, &"building")
		piece.queue_free())


func _remove(ids: Array, debris: bool) -> void:
	var wh := float(spec.get("wall_height", 2.8))
	for v: Variant in ids:
		var id := int(v)
		if not _shapes.has(id):
			continue
		var shape := _shapes[id]
		_shapes.erase(id)
		shape.queue_free()
		if _model == null:
			continue
		var box := _carve_box(id)
		var colour := _colour_of(id)
		_model.carve_box(box.position, box.end)
		if debris and _visual and is_inside_tree():
			var centre := _segments[id].get_center()
			# Wall pieces fly out from the building, roof pieces up.
			var out := Vector3.UP if centre.y >= wh - 0.1 else (Vector3(centre.x, 0.0, centre.z).normalized() + Vector3.UP * 0.5)
			VoxelDebris.burst(get_parent(), global_transform * centre, global_transform.basis * out, colour, &"building")


## Client: tells the audio what broke, one event per material at the middle of its pieces.
func _sound_breaks(ids: Array) -> void:
	var by_material: Dictionary[String, Array] = {}
	for v: Variant in ids:
		var id := int(v)
		if not _shapes.has(id):
			continue
		var m := str(segment_rules(id).get("name", material()))
		if not by_material.has(m):
			by_material[m] = []
		by_material[m].append(global_transform * _segments[id].get_center())
	for m: String in by_material:
		var points: Array = by_material[m]
		var mid := Vector3.ZERO
		for p: Vector3 in points:
			mid += p
		_sound(&"missions.surface_broke", mid / points.size(), m, points.size())


## Client only (sounds are for people): a surface sound event, `{position, material, count}`.
func _sound(topic: StringName, at: Vector3, material_name: String, count: int) -> void:
	if not _visual or not is_inside_tree():
		return
	EventBus.publish(topic, {"position": at, "material": material_name, "count": count})


## The colour of segment `id`'s voxels, for its debris: the first filled voxel found up the
## middle of its box.
func _colour_of(id: int) -> Color:
	var box := _carve_box(id)
	var c := box.get_center()
	for share: float in [0.5, 0.3, 0.7, 0.15, 0.85]:
		var colour := _model.colour_at(Vector3(c.x, box.position.y + box.size.y * share, c.z))
		if colour.a > 0.0:
			return colour
	return Color(0.5, 0.42, 0.33)


## The voxels segment `id` takes with it (a roof tile takes the sloping roof above it too).
func _carve_box(id: int) -> AABB:
	var wh := float(spec.get("wall_height", 2.8))
	var d := float(spec.get("depth", 4.0))
	var box := _segments[id].grow(voxel * 0.5)
	if box.position.y >= wh - 0.1:
		box = AABB(box.position, Vector3(box.size.x, d * 0.6 + 0.6, box.size.z))
	return box


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
