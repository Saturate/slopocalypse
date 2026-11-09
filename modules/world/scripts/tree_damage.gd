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
##
## The top's crown squashes as it lands, then dries out over `tree_wither_seconds`: the top
## is rebuilt a few times with its leaves browner and thinner until only the bare trunk and
## branches are left. Its age travels with it, so a late joiner sees it as dry as everyone.

const BARK := Color(0.33, 0.24, 0.16)
const LEAVES := Color(0.24, 0.36, 0.17)
const NEEDLES := Color(0.16, 0.3, 0.17)
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
## The top is rebuilt this many times as it withers (each rebuild costs tens of milliseconds).
const WITHER_STEPS := 3
## How long the crown takes to squash once the top has landed.
const COLLAPSE_SECONDS := 0.35
## The crown spreads sideways by this share of how much it squashes.
const COLLAPSE_SPREAD := 0.25
## The longest splinter sticking out of a break (metres, in the model).
const SPLINTER_LENGTH := 0.35
## Splinters per break.
const SPLINTER_COUNT := 8
## A break slants across the trunk by up to this much (metres), cut in this many steps.
const BREAK_SLANT := 0.45
const BREAK_STEPS := 5
## Stumps are built finer than trees (metres per voxel) so their splinters can be thin.
const STUMP_VOXEL := 0.05
## Freshly broken wood inside the trunk.
const FRESH_WOOD := Color(0.56, 0.44, 0.29)

var scatter: SceneryScatter
var visual := false
var config: Dictionary = {}

## Felled trees for good: id -> {direction, cut, blast (Vector4: local centre, radius),
## since (Time.get_ticks_msec() when it fell here, minus any age it arrived with)}.
var _felled: Dictionary[Vector2i, Dictionary] = {}
## Server: local heights of the bullets each standing tree has taken.
var _hits: Dictionary[Vector2i, PackedFloat32Array] = {}
## Clients: bullet bites per tree in the tree model's own space (x, y, z, radius).
var _bites: Dictionary[Vector2i, Array] = {}
## Clients: rebuild steps waiting, oldest first: {id, kind (fell or wither), stage, animate, model}.
var _jobs: Array[Dictionary] = []
## Clients: the fallen top of each felled tree in a loaded chunk (meta `wither`: how dry it is).
var _tops: Dictionary[Vector2i, MeshInstance3D] = {}


func is_felled(id: Vector2i) -> bool:
	return _felled.has(id)


func felled() -> Dictionary[Vector2i, Dictionary]:
	return _felled


## Seconds since tree `id` fell (0 if it is standing).
func age(id: Vector2i) -> float:
	if not _felled.has(id):
		return 0.0
	return (Time.get_ticks_msec() - int(_felled[id]["since"])) / 1000.0


## How withered tree `id`'s top is by now, in WITHER_STEPS steps from 0 (green) to 1 (bare).
func wither_of(id: Vector2i) -> float:
	var t := clampf(age(id) / maxf(float(config["tree_wither_seconds"]), 0.001), 0.0, 1.0)
	return floorf(t * WITHER_STEPS) / WITHER_STEPS


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
## towards `direction`. Remembered, so its chunk comes back with it down. `seconds_ago` is
## for trees a late joiner hears about: those lie still, already as dry as they are by now.
func fell(id: Vector2i, direction: Vector3, cut: float, blast: Vector4 = Vector4.ZERO, seconds_ago: float = 0.0) -> void:
	if _felled.has(id):
		return
	var flat := Vector3(direction.x, 0.0, direction.z)
	var since := Time.get_ticks_msec() - int(seconds_ago * 1000.0)
	_felled[id] = {"direction": flat.normalized() if flat.length() > 0.01 else Vector3.FORWARD, "cut": cut, "blast": blast, "since": since}
	_hits.erase(id)
	if scatter.tree_record(id).is_empty():
		return
	apply(id, seconds_ago <= 0.0)
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
		_jobs.append({"id": id, "kind": "fell", "stage": 0, "animate": animate})


## One rebuild step per frame: build the stump model, mesh it; build the top, mesh it and
## let it fall (hiding the standing tree at that moment, so nothing flickers).
func _process(_delta: float) -> void:
	var prof := Prof.start()
	_process_tick(_delta)
	Prof.stop(&"world/tree_damage:frame", prof)


func _process_tick(_delta: float) -> void:
	if visual:
		_queue_withering()
	if _jobs.is_empty():
		return
	var job: Dictionary = _jobs[0]
	var id: Vector2i = job["id"]
	if scatter.tree_record(id).is_empty():
		_jobs.pop_front()
		return
	var cut: float = _felled[id]["cut"]
	if job["kind"] == "wither":
		_wither_step(job, id, cut)
		return
	match int(job["stage"]):
		0, 2:
			job["model"] = _model(id, true, cut, wither_of(id)) if job["stage"] == 2 else _stump_model(id, cut)
		1:
			_add_stump(id, job["model"])
		3:
			_add_top(id, job["model"], bool(job["animate"]))
			_jobs.pop_front()
			return
	job["stage"] = int(job["stage"]) + 1


## A fallen top that has dried out a step further gets rebuilt drier.
func _queue_withering() -> void:
	for id: Vector2i in _tops.keys():
		var top := _tops[id]
		if not is_instance_valid(top):
			_tops.erase(id)
			continue
		if wither_of(id) <= float(top.get_meta(&"wither", 0.0)):
			continue
		if _jobs.any(func(j: Dictionary) -> bool: return j["id"] == id):
			continue
		_jobs.append({"id": id, "kind": "wither", "stage": 0})


## Build the drier top, then swap it in on the next frame.
func _wither_step(job: Dictionary, id: Vector2i, cut: float) -> void:
	if int(job["stage"]) == 0:
		job["wither"] = wither_of(id)
		job["model"] = _model(id, true, cut, job["wither"])
		job["stage"] = 1
		return
	_jobs.pop_front()
	var top: MeshInstance3D = _tops.get(id)
	if is_instance_valid(top):
		top.mesh = VoxGenerator.to_mesh(job["model"])
		top.set_meta(&"wither", job["wither"])


## The tree's own model with its bites (and blast) taken out and one side of the cut
## removed: everything above for the stump, below for the top, dried out by `wither`.
func _model(id: Vector2i, top: bool, cut: float, wither: float = 0.0) -> VoxelModel:
	var variant := scatter.tree_variant(id)
	var values := (variant["values"] as Dictionary).duplicate()
	values["wither"] = wither
	var model := (variant["gen"] as VoxGenerator).build(values)
	for b: Vector4 in _bites.get(id, []):
		model.carve_ellipsoid(Vector3(b.x, b.y, b.z), Vector3.ONE * b.w)
	var blast: Vector4 = _felled[id]["blast"]
	if blast.w > 0.0:
		model.carve_ellipsoid(Vector3(blast.x, blast.y, blast.z), Vector3.ONE * blast.w)
	_break(model, id, top, cut, float(variant["values"]["trunk"]) * 0.5, float(values["voxel"]))
	return model


## The stump as a model of its own: just the trunk up to the break, at a finer voxel size
## than the tree so the splinters can be thin. It is small, so the finer grid is cheap, and
## bare: low needles left on it would lie round its foot like a mat.
func _stump_model(id: Vector2i, cut: float) -> VoxelModel:
	var variant := scatter.tree_variant(id)
	var values: Dictionary = variant["values"]
	var pine: bool = variant["gen"] is VoxPineTree
	var trunk := float(values["trunk"])
	var h := float(values["height"])
	# The same taper as the generator's trunk: from the foot up to the crown (pine) or fork.
	var r_foot := trunk * 0.5
	var r_end := trunk * (0.12 if pine else 0.36)
	var y_end := h * (0.97 if pine else 0.42)
	var top := cut + SPLINTER_LENGTH
	var r_top := lerpf(r_foot, r_end, clampf((top + 0.3) / (y_end + 0.3), 0.0, 1.0))
	var model := VoxGenerator.new_model()
	model.setup(Vector3(r_foot * 2.0 + 0.4, top + 0.4, r_foot * 2.0 + 0.4), STUMP_VOXEL)
	var bark := VoxPineTree.BARK if pine else VoxLeafTree.BARK
	model.fill_capsule(Vector3(0, -0.3, 0), Vector3(0, top, 0), r_foot, r_top, bark, 0.15, hash(id))
	for b: Vector4 in _bites.get(id, []):
		model.carve_ellipsoid(Vector3(b.x, b.y, b.z), Vector3.ONE * b.w)
	var blast: Vector4 = _felled[id]["blast"]
	if blast.w > 0.0:
		model.carve_ellipsoid(Vector3(blast.x, blast.y, blast.z), Vector3.ONE * blast.w)
	_break(model, id, false, cut, lerpf(r_foot, r_end, clampf((cut + 0.3) / (y_end + 0.3), 0.0, 1.0)), STUMP_VOXEL)
	return model


## Snaps the model at `cut` the way wood breaks, not a saw cut: the break runs on a slant in
## steps, and thin pale splinters of different lengths stick out of it, up from the stump
## and down from the top. The same seed per tree, so every machine breaks it alike.
func _break(model: VoxelModel, id: Vector2i, top: bool, cut: float, radius: float, voxel: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var slope := rng.randf_range(-1.0, 1.0) * BREAK_SLANT
	for k in BREAK_STEPS:
		var x0 := -FAR if k == 0 else lerpf(-radius, radius, float(k) / BREAK_STEPS)
		var x1 := FAR if k == BREAK_STEPS - 1 else lerpf(-radius, radius, float(k + 1) / BREAK_STEPS)
		var h := cut + slope * ((k + 0.5) / BREAK_STEPS - 0.5)
		if top:
			model.carve_box(Vector3(x0, -FAR, -FAR), Vector3(x1, h, FAR))
		else:
			model.carve_box(Vector3(x0, h, -FAR), Vector3(x1, FAR, FAR))
	# Only the broken face is bare wood; the bark round its sides stays dark.
	var high := absf(slope) * 0.5 + voxel
	var from := cut - high if top else cut - voxel
	var to := cut + voxel if top else cut + high
	model.paint_box(Vector3(-radius * 0.8, from, -radius * 0.8), Vector3(radius * 0.8, to, radius * 0.8), FRESH_WOOD, 0.15, int(rng.seed))
	var up := -1.0 if top else 1.0
	for n in SPLINTER_COUNT:
		var angle := rng.randf() * TAU
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var base := out * radius * rng.randf_range(0.25, 0.85) + Vector3(0.0, cut, 0.0)
		var length := rng.randf_range(SPLINTER_LENGTH * 0.3, SPLINTER_LENGTH)
		var tip := base + Vector3(0.0, up * length, 0.0) + out * length * rng.randf_range(0.05, 0.3)
		var thick := voxel * rng.randf_range(0.8, 1.6)
		model.fill_capsule(base, tip, thick, voxel * 0.4, FRESH_WOOD, 0.15, int(rng.seed) + n)


func _add_stump(id: Vector2i, model: VoxelModel) -> void:
	var stump := MeshInstance3D.new()
	stump.name = "Stump%d" % id.y
	stump.mesh = VoxGenerator.to_mesh(model)
	stump.transform = scatter.tree_record(id)["xform"]
	stump.visibility_range_end = float(config["load_distance"])
	scatter.chunk_node(id.x).add_child(stump)


## The top hangs from a pivot at the cut, tips over and slides down to lie on the ground,
## then its crown squashes under its own weight and sheds leaves.
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
	top.set_meta(&"wither", wither_of(id))
	pivot.add_child(top)
	scatter.chunk_node(id.x).add_child(pivot)
	scatter.hide_standing_tree(id)
	_tops[id] = top
	var start := xform * Vector3(0.0, cut, 0.0)
	var rest := (tree["at"] as Vector3) + Vector3.UP * float(tree["radius"])
	var axis := Vector3.UP.cross(info["direction"] as Vector3).normalized()
	var collapse := float(config["tree_collapse"])
	# t: how far it has tipped; s: how far the crown has squashed (flatter, a little wider).
	var pose := func(t: float, s: float) -> void:
		var k := collapse * s
		var squash := Basis.from_scale(Vector3(1.0 + k * COLLAPSE_SPREAD, 1.0 - k, 1.0 + k * COLLAPSE_SPREAD))
		pivot.transform = Transform3D(squash * Basis(axis, FALL_ANGLE * t), start.lerp(rest, t * t))
	if not animate:
		pose.call(1.0, 1.0)
		return
	pose.call(0.0, 0.0)
	var leaves := NEEDLES if tree["kind"] == "pine" else LEAVES
	# Slow to start, then faster: it leans, then goes; on landing the crown gives way.
	var tween := pivot.create_tween()
	tween.tween_method(func(t: float) -> void: pose.call(t, 0.0), 0.0, 1.0, float(config["tree_fall_seconds"])).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		var crown := pivot.global_transform * top.transform * top.mesh.get_aabb().get_center()
		VoxelDebris.burst(scatter, crown, Vector3.UP, leaves, SPLINTERS * 3, 3.5))
	tween.tween_method(func(s: float) -> void: pose.call(1.0, s), 0.0, 1.0, COLLAPSE_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _local(id: Vector2i, point: Vector3) -> Vector3:
	return (scatter.tree_record(id)["xform"] as Transform3D).affine_inverse() * point


func _scale(id: Vector2i) -> float:
	return (scatter.tree_record(id)["xform"] as Transform3D).basis.get_scale().x
