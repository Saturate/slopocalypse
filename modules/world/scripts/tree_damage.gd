class_name TreeDamage
extends Node
## Trees taking damage and coming down, for SceneryScatter (which owns where trees stand).
##
## The server counts bullets per trunk and decides when a tree falls and where it is cut:
## at the average height of the shots, or low down for an explosion. Every machine then
## cuts it there: the trunk's collision becomes a stump, and clients rebuild that one tree
## as its own voxel model in two parts, a stump left standing and the top that tips over
## from the cut, both notched where the bullets went in. A rebuild costs tens of
## milliseconds, so the parts are built one step per frame from a queue.
##
## Shots throw bark splinters on clients; the bites they leave are remembered per tree so
## the notch shows when it falls.

const BARK := Color(0.33, 0.24, 0.16)
const LEAVES := Color(0.24, 0.36, 0.17)
## A bullet's bite out of a trunk, in metres.
const BITE := 0.22
## How far a felled top tips: not quite flat, as if it came to rest on its branches.
const FALL_ANGLE := PI * 0.47
## Explosions cut trees between these heights above the foot.
const BLAST_CUT_MIN := 0.3
const BLAST_CUT_MAX := 1.6
## Bullet cuts never go higher than this share of the trunk's collision height.
const CUT_MAX_SHARE := 0.9
const SPLINTERS := 6
## The cut-away part of a model is everything in this half-size box above or below the cut.
const FAR := 100.0

var scatter: SceneryScatter
var visual := false
var config: Dictionary = {}

## Felled trees for good: id -> {direction, cut, blast (Vector4: local centre, radius)}.
var _felled: Dictionary[Vector2i, Dictionary] = {}
## Server: local heights of the bullets each standing tree has taken.
var _hits: Dictionary[Vector2i, PackedFloat32Array] = {}
## Clients: bullet bites per tree in the tree model's own space (x, y, z, radius).
var _bites: Dictionary[Vector2i, Array] = {}
## Clients: rebuild steps waiting, oldest first: {id, stage, animate, model}.
var _jobs: Array[Dictionary] = []


func is_felled(id: Vector2i) -> bool:
	return _felled.has(id)


func felled() -> Dictionary[Vector2i, Dictionary]:
	return _felled


## Server: a bullet hit the trunk `id` at `point`. Once it has taken `tree_hits`, returns
## {cut} for felling it there; otherwise null.
func server_shoot(id: Vector2i, point: Vector3) -> Variant:
	if _felled.has(id):
		return null
	var heights: PackedFloat32Array = _hits.get(id, PackedFloat32Array())
	heights.append(_local(id, point).y)
	_hits[id] = heights
	if heights.size() < int(config["tree_hits"]):
		return null
	_hits.erase(id)
	var sum := 0.0
	for h in heights:
		sum += h
	var top := float(scatter.tree_record(id)["trunk_height"]) * CUT_MAX_SHARE
	return {"cut": clampf(sum / heights.size(), BLAST_CUT_MIN, top)}


## Server: what an explosion at `center` does to tree `id`: where it is cut, and the chunk
## of tree the blast takes with it (local centre and radius).
func server_blast(id: Vector2i, center: Vector3, radius: float) -> Dictionary:
	var local := _local(id, center)
	var scale := _scale(id)
	return {"cut": clampf(local.y, BLAST_CUT_MIN, BLAST_CUT_MAX), "blast": Vector4(local.x, local.y, local.z, radius * 0.6 / scale)}


## Clients: a bullet bit the trunk `id` at `point`: splinters fly, and the bite is kept
## for when the tree comes down.
func bite(id: Vector2i, point: Vector3, from: Vector3) -> void:
	if not visual or _felled.has(id):
		return
	var local := _local(id, point)
	var bites: Array = _bites.get(id, [])
	bites.append(Vector4(local.x, local.y, local.z, BITE / _scale(id)))
	_bites[id] = bites
	VoxelDebris.burst(scatter, point, (from - point).normalized(), BARK, SPLINTERS, 3.0)


## Every machine: tree `id` is cut at `cut` (metres above its foot) and the top falls
## towards `direction`. Remembered, so its chunk comes back with it down.
func fell(id: Vector2i, direction: Vector3, cut: float, blast: Vector4 = Vector4.ZERO) -> void:
	if _felled.has(id):
		return
	var flat := Vector3(direction.x, 0.0, direction.z)
	_felled[id] = {"direction": flat.normalized() if flat.length() > 0.01 else Vector3.FORWARD, "cut": cut, "blast": blast}
	_hits.erase(id)
	if scatter.tree_record(id).is_empty():
		return
	apply(id, true)
	if visual:
		var at := scatter.tree_record(id)["xform"] as Transform3D
		VoxelDebris.burst(scatter, at * Vector3(0.0, cut, 0.0), Vector3.UP, BARK, SPLINTERS * 2, 4.0)
		if blast.w > 0.0:
			VoxelDebris.burst(scatter, at * Vector3(blast.x, blast.y, blast.z), Vector3.UP, LEAVES, SPLINTERS * 2, 6.0)


## A felled tree in a loaded chunk: its trunk collision becomes the stump, its sight blocker
## goes, and on clients its two parts are queued for building.
func apply(id: Vector2i, animate: bool) -> void:
	var tree := scatter.tree_record(id)
	var info := _felled[id]
	var leaves := tree["leaves"] as CollisionShape3D
	if is_instance_valid(leaves):
		# Disabled now, so the same physics step stops hitting it; freed after.
		leaves.disabled = true
		leaves.queue_free()
	var trunk := tree["trunk"] as CollisionShape3D
	if is_instance_valid(trunk):
		var capsule := (trunk.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
		var stump := maxf(float(info["cut"]) * _scale(id), capsule.radius * 2.0)
		capsule.height = stump
		trunk.shape = capsule
		trunk.position = (tree["at"] as Vector3) + Vector3.UP * stump * 0.5
		trunk.set_meta(&"stump", true)
	if visual:
		_jobs.append({"id": id, "stage": 0, "animate": animate})


## One rebuild step per frame: build the stump model, mesh it; build the top, mesh it and
## let it fall (hiding the standing tree at that moment, so nothing flickers).
func _process(_delta: float) -> void:
	if _jobs.is_empty():
		return
	var job: Dictionary = _jobs[0]
	var id: Vector2i = job["id"]
	if scatter.tree_record(id).is_empty():
		_jobs.pop_front()
		return
	var cut: float = _felled[id]["cut"]
	match int(job["stage"]):
		0, 2:
			job["model"] = _model(id, job["stage"] == 2, cut)
		1:
			_add_stump(id, job["model"])
		3:
			_add_top(id, job["model"], bool(job["animate"]))
			_jobs.pop_front()
			return
	job["stage"] = int(job["stage"]) + 1


## The tree's own model with its bites (and blast) taken out and one side of the cut
## removed: everything above for the stump, below for the top.
func _model(id: Vector2i, top: bool, cut: float) -> VoxelModel:
	var variant := scatter.tree_variant(id)
	var model := (variant["gen"] as VoxGenerator).build(variant["values"])
	for b: Vector4 in _bites.get(id, []):
		model.carve_ellipsoid(Vector3(b.x, b.y, b.z), Vector3.ONE * b.w)
	var blast: Vector4 = _felled[id]["blast"]
	if blast.w > 0.0:
		model.carve_ellipsoid(Vector3(blast.x, blast.y, blast.z), Vector3.ONE * blast.w)
	if top:
		model.carve_box(Vector3(-FAR, -FAR, -FAR), Vector3(FAR, cut, FAR))
	else:
		model.carve_box(Vector3(-FAR, cut, -FAR), Vector3(FAR, FAR, FAR))
	return model


func _add_stump(id: Vector2i, model: VoxelModel) -> void:
	var stump := MeshInstance3D.new()
	stump.name = "Stump%d" % id.y
	stump.mesh = VoxGenerator.to_mesh(model)
	stump.transform = scatter.tree_record(id)["xform"]
	stump.visibility_range_end = float(config["load_distance"])
	scatter.chunk_node(id.x).add_child(stump)


## The top hangs from a pivot at the cut, tips over and slides down to lie on the ground.
func _add_top(id: Vector2i, model: VoxelModel, animate: bool) -> void:
	var tree := scatter.tree_record(id)
	var info := _felled[id]
	var xform: Transform3D = tree["xform"]
	var cut: float = info["cut"]
	var pivot := Node3D.new()
	pivot.name = "Felled%d" % id.y
	var top := MeshInstance3D.new()
	top.mesh = VoxGenerator.to_mesh(model)
	top.transform = Transform3D(xform.basis, xform.basis * Vector3(0.0, -cut, 0.0))
	top.visibility_range_end = float(config["load_distance"])
	pivot.add_child(top)
	scatter.chunk_node(id.x).add_child(pivot)
	scatter.hide_standing_tree(id)
	var start := xform * Vector3(0.0, cut, 0.0)
	var rest := (tree["at"] as Vector3) + Vector3.UP * float(tree["radius"])
	var axis := Vector3.UP.cross(info["direction"] as Vector3).normalized()
	var tip := func(t: float) -> void:
		pivot.transform = Transform3D(Basis(axis, FALL_ANGLE * t), start.lerp(rest, t * t))
	if not animate:
		tip.call(1.0)
		return
	tip.call(0.0)
	# Slow to start, then faster: it leans, then goes.
	var tween := pivot.create_tween()
	tween.tween_method(tip, 0.0, 1.0, float(config["tree_fall_seconds"])).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _local(id: Vector2i, point: Vector3) -> Vector3:
	return (scatter.tree_record(id)["xform"] as Transform3D).affine_inverse() * point


func _scale(id: Vector2i) -> float:
	return (scatter.tree_record(id)["xform"] as Transform3D).basis.get_scale().x
