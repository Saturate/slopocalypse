class_name CitySite
extends Node3D
## A city on the ground (CityLayout): levelled, cleared of trees and grass, its streets laid
## in pale city asphalt with zebra crossings by the junctions, pavements a kerb high round
## every block and over the square (paving slabs edged in kerb stones, setts in the
## courtyards, a grate round each street tree), street trees, and its apartment blocks
## (CityBuilding) put up a few a frame so loading it doesn't stall. Built the same on the
## server and every client from the layout's seed; the server gets the collision only.
##
## Street lamps belong to the lights module: `lamp_spots()` says where they go.
##
## Origin at the city's middle, on its level ground; -z toward the road it joins.

const KERB := 0.15
const PAVING := Color(0.62, 0.61, 0.58)
const SQUARE_PAVING := Color(0.64, 0.59, 0.51)
const KERB_STONE := Color(0.74, 0.73, 0.7)
const SETTS := Color(0.5, 0.47, 0.43)
const GRATE := Color(0.17, 0.17, 0.18)
const SOIL := Color(0.3, 0.23, 0.16)
## Paving voxels a kerb high, so a block's paving is one layer.
const PAVING_VOXEL := KERB
## Kerb stones are laid in lengths of a metre.
const KERB_STONE_LENGTH := 1.0
## A tree grate's side and the soil square in its middle.
const GRATE_SIZE := Vector2(1.2, 0.5)
## The share of paving slabs a shade off the rest.
const RELAID := 0.18
const TREE_VOXEL := 0.1
const TREE_VARIANTS := 3
## Where VoxLeafTree's trunk forks, as a share of its height: the trunk's collision stops there.
const TREE_FORK := 0.42
## Each tree turned by the golden angle from the last, so neighbours never look alike.
const TREE_TURN := 2.39996

## city.json.
var config: Dictionary = {}
var plan: Dictionary = {}
var buildings: Array[CityBuilding] = []
## The street in from the road (see `lead_in`); empty until the city module sets it.
var approach: Dictionary = {}
## The hand-made blocks standing in the city (#339).
var blocks_placed: Array[CityBlockNode] = []

var _queue: Array[Dictionary] = []
var _body := RID()
var _shapes: Array[RID] = []
var _visual := DisplayServer.get_name() != "headless"


func _ready() -> void:
	var t := Prof.start()
	plan = CityLayout.make(config, int(config.get("seed", 1)), CityBlock.catalogue())
	_body = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_collision_layer(_body, PhysicsLayers.SOLID)
	PhysicsServer3D.body_set_collision_mask(_body, 0)
	PhysicsServer3D.body_attach_object_instance_id(_body, get_instance_id())
	PhysicsServer3D.body_set_space(_body, get_world_3d().space)
	PhysicsServer3D.body_set_state(_body, PhysicsServer3D.BODY_STATE_TRANSFORM, global_transform)
	for block: Rect2 in plan["blocks"]:
		_box(Vector3(block.get_center().x, KERB / 2.0, block.get_center().y), Vector3(block.size.x, KERB, block.size.y))
	var trunk := float(config.get("tree_trunk", 0.3))
	var fork := float(config.get("tree_height", 6.5)) * TREE_FORK
	for at: Vector2 in plan["trees"]:
		_box(Vector3(at.x, KERB + fork / 2.0, at.y), Vector3(trunk, fork, trunk))
	if _visual:
		for block: Rect2 in plan["blocks"]:
			_paving(block)
		_streets()
		_trees()
	_queue.assign(plan["buildings"])
	for h: Dictionary in plan["handmade"]:
		var node := CityBlockNode.new()
		node.name = "Block_%s" % h["name"]
		node.block = CityBlock.load_named(str(h["name"]))
		node.variation_seed = int(h["variation"])
		node.builds_per_frame = maxi(int(config.get("builds_per_frame", 2)), 1)
		var centre: Vector2 = h["centre"]
		node.transform = Transform3D(Basis(Vector3.UP, float(h["yaw"])), Vector3(centre.x, KERB, centre.y))
		add_child(node)
		blocks_placed.append(node)
	Prof.stop(&"city/site_ready", t)


## Buildings still to put up.
func pending() -> int:
	var n := _queue.size()
	for b in blocks_placed:
		n += b.pending()
	return n


func _process(_delta: float) -> void:
	if _queue.is_empty():
		return
	var t := Prof.start()
	for i in maxi(int(config.get("builds_per_frame", 2)), 1):
		if _queue.is_empty():
			break
		_put_up(_queue.pop_front())
	Prof.stop(&"city/site", t)


## Everything at once (tests and tools).
func build_all() -> void:
	while not _queue.is_empty():
		_put_up(_queue.pop_front())
	for b in blocks_placed:
		b.build_all()


## Where the street lamps stand, in world space: on the pavement top, each turned so its arm
## (+x) reaches out over its street.
func lamp_spots() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for lamp: Dictionary in plan.get("lamps", []):
		var at: Vector2 = lamp["at"]
		var toward: Vector2 = lamp["out"]
		out.append(global_transform * Transform3D(Basis(Vector3.UP, atan2(-toward.y, toward.x)), Vector3(at.x, KERB, at.y)))
	return out


func _put_up(b: Dictionary) -> void:
	var foot: Rect2 = b["footprint"]
	var building := CityBuilding.new()
	building.name = "Building%d" % buildings.size()
	building.params = b["params"]
	# On the pavement's top, so the front steps meet it.
	building.transform = Transform3D(Basis(Vector3.UP, float(b["yaw"])), Vector3(foot.get_center().x, KERB, foot.get_center().y))
	add_child(building)
	buildings.append(building)


func _box(centre: Vector3, size: Vector3) -> void:
	var shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(shape, size / 2.0)
	PhysicsServer3D.body_add_shape(_body, shape, Transform3D(Basis.IDENTITY, centre))
	_shapes.append(shape)


## A block's paving in voxels, one layer a kerb high: kerb stones round the edge, slabs on
## the pavement (some a shade off, as relaid slabs are), setts in the courtyard, larger
## slabs over the square, and a grate round each tree.
func _paving(block: Rect2) -> void:
	var square := (plan["squares"] as Array).has(block)
	var v := PAVING_VOXEL
	var tile := float(config.get("tile_size", 0.6)) * (2.0 if square else 1.0)
	var kerb := float(config.get("kerb_width", 0.3))
	var pave := float(config.get("pavement", 3.0))
	var seed := int(config.get("seed", 1)) + int(block.position.x * 13.0 + block.position.y * 7.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var base := SQUARE_PAVING if square else PAVING
	var joint := base.darkened(0.08)
	var m := VoxGenerator.new_model()
	m.setup(Vector3(block.size.x, KERB, block.size.y), v)
	var c := block.get_center()
	var local := func(r: Rect2) -> Rect2: return Rect2(r.position - c, r.size)
	var all := Rect2(-block.size / 2.0, block.size)
	m.fill_box(Vector3(all.position.x, 0.0, all.position.y), Vector3(all.end.x, KERB, all.end.y), base, 0.0, 0)
	# Relaid slabs only where paving shows: under the buildings it never does.
	var built := all.grow(-pave)
	var x := all.position.x + kerb
	while x < all.end.x - kerb:
		var y := all.position.y + kerb
		while y < all.end.y - kerb:
			var slab := Rect2(x, y, tile, tile)
			if (square or not built.grow(-tile).encloses(slab)) and rng.randf() < RELAID:
				m.paint_box(Vector3(x, 0.0, y), Vector3(minf(x + tile, all.end.x - kerb), KERB, minf(y + tile, all.end.y - kerb)), base * rng.randf_range(0.93, 1.05), 0.0, 0)
			y += tile
		x += tile
	# Joints between the slabs: a thin darker line every slab, both ways.
	x = all.position.x + kerb
	while x < all.end.x - kerb:
		m.paint_box(Vector3(x - v / 2.0, 0.0, all.position.y), Vector3(x + v / 2.0, KERB, all.end.y), joint, 0.0, 0)
		x += tile
	var z := all.position.y + kerb
	while z < all.end.y - kerb:
		m.paint_box(Vector3(all.position.x, 0.0, z - v / 2.0), Vector3(all.end.x, KERB, z + v / 2.0), joint, 0.0, 0)
		z += tile
	if not square:
		for yard: Rect2 in plan["yards"]:
			if block.encloses(yard):
				var r: Rect2 = local.call(yard)
				m.paint_box(Vector3(r.position.x, 0.0, r.position.y), Vector3(r.end.x, KERB, r.end.y), SETTS, 0.16, seed)
		# The gateways' floors in setts too, out to the pavement.
		for passage: Rect2 in plan["passages"]:
			if block.encloses(passage):
				var r: Rect2 = local.call(passage)
				m.paint_box(Vector3(r.position.x, 0.0, r.position.y), Vector3(r.end.x, KERB, r.end.y), SETTS, 0.16, seed + 1)
	# Kerb stones: a ring round the edge, each stone a metre long, every other a shade off.
	for side in 4:
		var along_x := side < 2
		var length := all.size.x if along_x else all.size.y
		var k := 0
		var at := 0.0
		while at < length - 0.001:
			var shade := KERB_STONE * (1.0 if k % 2 == 0 else 0.95)
			var to := minf(at + KERB_STONE_LENGTH, length)
			var lo: Vector3
			var hi: Vector3
			if along_x:
				var z0 := all.position.y if side == 0 else all.end.y - kerb
				lo = Vector3(all.position.x + at, 0.0, z0)
				hi = Vector3(all.position.x + to, KERB, z0 + kerb)
			else:
				var x0 := all.position.x if side == 2 else all.end.x - kerb
				lo = Vector3(x0, 0.0, all.position.y + at)
				hi = Vector3(x0 + kerb, KERB, all.position.y + to)
			m.paint_box(lo, hi, shade, 0.03, seed + k)
			at = to
			k += 1
	for tree: Vector2 in plan["trees"]:
		if block.has_point(tree):
			var p := tree - c
			m.paint_box(Vector3(p.x - GRATE_SIZE.x / 2.0, 0.0, p.y - GRATE_SIZE.x / 2.0), Vector3(p.x + GRATE_SIZE.x / 2.0, KERB, p.y + GRATE_SIZE.x / 2.0), GRATE, 0.05, seed)
			m.paint_box(Vector3(p.x - GRATE_SIZE.y / 2.0, 0.0, p.y - GRATE_SIZE.y / 2.0), Vector3(p.x + GRATE_SIZE.y / 2.0, KERB, p.y + GRATE_SIZE.y / 2.0), SOIL, 0.15, seed)
	var mesh := MeshInstance3D.new()
	mesh.name = "Paving"
	mesh.mesh = VoxGenerator.to_mesh(m)
	mesh.position = Vector3(c.x, 0.0, c.y)
	add_child(mesh)


## Every street as stretches between junctions (a dashed line down the middle, zebra
## crossings near the ends) and plain squares of asphalt where they meet, sunk so the
## surface sits on the level ground.
func _streets() -> void:
	var lines: Array = plan["lines"]
	var widths: Array = plan["widths"]
	var n := widths.size() - 1
	var piece := 0
	for axis in 2:
		for i in n + 1:
			var at := float(lines[axis][i])
			var w := float(widths[i])
			for k in n:
				var s0 := float(lines[1 - axis][k]) + float(widths[k])
				var s1 := float(lines[1 - axis][k + 1])
				var rect := Rect2(at, s0, w, s1 - s0) if axis == 0 else Rect2(s0, at, s1 - s0, w)
				_road(rect, axis == 1, true, piece)
				piece += 1
	for i in n + 1:
		for k in n + 1:
			_road(Rect2(float(lines[0][i]), float(lines[1][k]), float(widths[i]), float(widths[k])), false, false, piece)
			piece += 1


## Where a street piece over `rect` goes: its asphalt top at the city's level, where the
## levelled ground is, so nobody stands sunk into it.
static func street_transform(rect: Rect2, along_x: bool) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, PI / 2.0) if along_x else Basis.IDENTITY, Vector3(rect.get_center().x, -VoxRoad.BED - VoxRoad.SURFACE, rect.get_center().y))


## Where the approach street goes: along z from `from` (at the road, `drop` metres above the
## city's level, below if negative) to `to` (the ring street), at `x`, tilted so its top
## follows the ramp the ground is levelled to.
static func approach_transform(x: float, from: float, to: float, drop: float) -> Transform3D:
	var basis := Basis(Vector3.RIGHT, atan2(drop, to - from))
	var centre := Vector3(x, drop / 2.0, (from + to) / 2.0)
	return Transform3D(basis, centre + basis * Vector3(0.0, -VoxRoad.BED - VoxRoad.SURFACE, 0.0))


## The street from the road into the city, in the city's own metres: `{x, width, road, edge,
## from, to, edge_drop, drop}`: from the road's middle (`road`), drawn from its edge (`edge`,
## `edge_drop` over the city's level) along the road's band to `from` (`drop` over it), then
## a ramp to the city at `to` (see `approach_transform`); drawn as it is set.
func lead_in(info: Dictionary) -> void:
	approach = info
	if not _visual or info.is_empty():
		return
	var x := float(info["x"])
	var drop := float(info["drop"])
	if float(info["from"]) > float(info["edge"]):
		var rise := float(info["edge_drop"]) - drop
		_approach_piece("ApproachFlat", Vector2(float(info["from"]) - float(info["edge"]), rise).length(), approach_transform(x, float(info["edge"]), float(info["from"]), rise).translated(Vector3.UP * drop))
	_approach_piece("Approach", Vector2(float(info["to"]) - float(info["from"]), drop).length(), approach_transform(x, float(info["from"]), float(info["to"]), drop))


func _approach_piece(name_: String, length: float, where: Transform3D) -> void:
	var width := float(approach["width"])
	var rgb: Array = config.get("asphalt", [0.43, 0.43, 0.42])
	var model := VoxRoad.new().build({
		"seed": 5, "length": length, "lanes": 2.0, "lane_width": width / 2.0, "shoulder": 0.0,
		"wear": 0.2, "potholes": 0.0, "edges": 0.0, "asphalt": Color(float(rgb[0]), float(rgb[1]), float(rgb[2])),
	})
	var part := MeshInstance3D.new()
	part.name = name_
	part.mesh = VoxGenerator.to_mesh(model)
	part.transform = where
	add_child(part)


func _road(rect: Rect2, along_x: bool, marked: bool, piece: int) -> void:
	var length := rect.size.x if along_x else rect.size.y
	var width := rect.size.y if along_x else rect.size.x
	var rgb: Array = config.get("asphalt", [0.43, 0.43, 0.42])
	var asphalt := Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))
	var values := {
		"seed": piece + 7, "length": length, "lanes": 2.0, "lane_width": width / 2.0, "shoulder": 0.0,
		"wear": 0.2, "potholes": 0.0, "edges": 0.0, "asphalt": asphalt,
	}
	if not marked:
		values["centre"] = 0.0
	var model := VoxRoad.new().build(values)
	var where := street_transform(rect, along_x)
	for crossing: Rect2 in plan["crossings"]:
		if rect.grow(0.01).encloses(crossing):
			_zebra(model, where, crossing, asphalt)
	var part := MeshInstance3D.new()
	part.name = "Street%d" % piece
	part.mesh = VoxGenerator.to_mesh(model)
	part.transform = where
	add_child(part)


## White bars along the traffic, across the street kerb to kerb, painted over the asphalt
## (after clearing the centre line under them).
func _zebra(model: VoxelModel, where: Transform3D, crossing: Rect2, asphalt: Color) -> void:
	var inverse := where.affine_inverse()
	var a := inverse * Vector3(crossing.position.x, 0.0, crossing.position.y)
	var b := inverse * Vector3(crossing.end.x, 0.0, crossing.end.y)
	var lo := Vector2(minf(a.x, b.x), minf(a.z, b.z))
	var hi := Vector2(maxf(a.x, b.x), maxf(a.z, b.z))
	var v := model.voxel_size()
	var top := VoxRoad.BED + VoxRoad.SURFACE
	model.paint_box(Vector3(lo.x, top - v * 0.9, lo.y), Vector3(hi.x, top + v, hi.y), asphalt, 0.07, 0)
	var stripe := float(config.get("zebra_stripe", 0.5))
	var x := lo.x + stripe
	while x + stripe <= hi.x - stripe * 0.5:
		model.paint_box(Vector3(x, top - v * 0.9, lo.y), Vector3(x + stripe, top + v, hi.y), VoxRoad.WHITE, 0.04, 0)
		x += stripe * 2.0


## Street trees: a few variants built once, one drawn at each spot, each turned its own way.
func _trees() -> void:
	var spots: Array = plan["trees"]
	if spots.is_empty():
		return
	var meshes: Array[ArrayMesh] = []
	for i in TREE_VARIANTS:
		meshes.append(VoxGenerator.to_mesh(VoxLeafTree.new().build({
			"seed": int(config.get("seed", 1)) + 40 + i, "height": float(config.get("tree_height", 6.5)) + i * 0.4,
			"crown": float(config.get("tree_crown", 1.3)), "trunk": float(config.get("tree_trunk", 0.3)), "branches": 5.0, "voxel": TREE_VOXEL,
		})))
	for i in spots.size():
		var at: Vector2 = spots[i]
		var tree := MeshInstance3D.new()
		tree.name = "Tree%d" % i
		tree.mesh = meshes[i % meshes.size()]
		tree.transform = Transform3D(Basis(Vector3.UP, float(i) * TREE_TURN), Vector3(at.x, KERB, at.y))
		add_child(tree)


func _exit_tree() -> void:
	if _body.is_valid():
		PhysicsServer3D.free_rid(_body)
		_body = RID()
	for shape in _shapes:
		PhysicsServer3D.free_rid(shape)
	_shapes.clear()
