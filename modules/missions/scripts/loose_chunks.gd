class_name LooseChunks
extends RefCounted
## A broken piece of building falls apart into fragments of its own voxels, and the fragments
## become its rubble, the same on every machine without anything being sent.
##
## Everything comes from a seed (the building's, and the piece's number): where the piece
## cracks (seed points the voxel kit's fracture breaks round, ragged, never splitting a brick),
## how each fragment is thrown, how it tumbles and where it comes to rest (lying on its
## thinnest side at a seeded heading, on level ground). No physics decides any of it, because
## physics never comes out quite the same on two machines; each fragment follows its worked-out
## fall, so the server and every client, and anyone joining later, put it in the same place.
## Landed fragments are solid (cover you can climb); glass shards lie there but stop nothing.

const CONFIG := "res://modules/missions/data/missions.json"
const GRAVITY := 9.8

static var _cfg: Dictionary = {}


static func config() -> Dictionary:
	if _cfg.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
		var buildings: Dictionary = (data as Dictionary).get("buildings", {}) if data is Dictionary else {}
		_cfg = buildings.get("chunks", {}) as Dictionary
	return _cfg


## Breaks the voxels of `box` (local to `building`) of `model` into fragments and lets them
## fall, pushed along `push` (local, metres per second). `piece` and `seed` pick the cracks and
## falls. `glass`: shards, see-through, stopping nothing. `animate` false puts them straight
## where they come to rest (someone joining late). Returns the fragments.
static func break_up(building: Node3D, model: VoxelModel, box: AABB, piece: int, push: Vector3, seed: int, glass := false, animate := true) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if building == null or not building.is_inside_tree() or model == null:
		return out
	var cfg := config()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, piece])
	var size := float(cfg.get("shard_size", 0.2)) if glass else float(cfg.get("size", 0.45))
	var most := int(cfg.get("max_shards", 24)) if glass else int(cfg.get("max_per_piece", 10))
	var count := clampi(roundi(box.size.x * box.size.y * box.size.z / (size * size * size)), 2, most)
	var seeds := PackedVector3Array()
	for i in count:
		seeds.append(box.position + box.size * Vector3(rng.randf(), rng.randf(), rng.randf()))
	var unit := 0 if glass else VoxMaterials.index_of("brick")
	var pieces: Array = model.fracture(box.position, box.end, seeds, unit, float(cfg.get("jag", 1.5)), seed + piece)
	for k in pieces.size():
		var frag: Dictionary = pieces[k]
		var plan := fall_plan(frag, push, hash([seed, piece, k]))
		var node := _fragment(frag["model"], frag["lo"], frag["hi"], glass)
		building.get_parent().add_child(node)
		if animate:
			node.global_transform = building.global_transform * pose(plan, 0.0)
			var tween := node.create_tween()
			tween.tween_method(func(s: float) -> void:
				if is_instance_valid(building):
					node.global_transform = building.global_transform * pose(plan, s), 0.0, 1.0, float(plan["seconds"]))
			tween.tween_callback(_land.bind(node, glass))
		else:
			node.global_transform = building.global_transform * pose(plan, 1.0)
			_land(node, glass)
		out.append(node)
	return out


## Where a fragment `{offset, lo, hi}` starts and comes to rest (local to the building), how
## long it falls, and how it tumbles: all from `seed`.
static func fall_plan(frag: Dictionary, push: Vector3, seed: int) -> Dictionary:
	var cfg := config()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var lo: Vector3 = frag["lo"]
	var hi: Vector3 = frag["hi"]
	var mid := (lo + hi) / 2.0
	var extent := hi - lo
	var start_centre: Vector3 = (frag["offset"] as Vector3) + mid
	# Lie on its thinnest side, turned to a seeded heading.
	var thin := 0 if extent.x <= extent.y and extent.x <= extent.z else (1 if extent.y <= extent.z else 2)
	var flip := 1.0 if rng.randf() < 0.5 else -1.0
	var lay := Basis.IDENTITY
	if thin == 0:
		lay = Basis(Vector3.BACK, flip * PI / 2.0)
	elif thin == 2:
		lay = Basis(Vector3.RIGHT, flip * PI / 2.0)
	var rest_basis := Basis(Vector3.UP, rng.randf() * TAU) * lay
	var half := extent[thin] / 2.0
	var scatter := float(cfg.get("scatter", 1.5))
	var v := push + Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.0, 1.0), rng.randf_range(-1.0, 1.0)) * scatter
	# Down to where its thinnest half rests on the ground (local y 0).
	var drop := maxf(start_centre.y - half, 0.0)
	var seconds := maxf((v.y + sqrt(v.y * v.y + 2.0 * GRAVITY * drop)) / GRAVITY, 0.15)
	var rest_centre := Vector3(start_centre.x + v.x * seconds, half, start_centre.z + v.z * seconds)
	var axis := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
	if axis.is_zero_approx():
		axis = Vector3.UP
	return {
		"mid": mid, "start_centre": start_centre, "rest_centre": rest_centre, "rest_basis": rest_basis,
		"velocity": v, "seconds": seconds, "axis": axis.normalized(), "turns": rng.randi_range(1, int(cfg.get("turns", 2))),
	}


## The fragment's transform (local to the building) `s` of the way (0..1) through its fall:
## along its throw under gravity, tumbling whole turns that end exactly in its resting turn.
static func pose(plan: Dictionary, s: float) -> Transform3D:
	var rest_basis: Basis = plan["rest_basis"]
	var rest: Vector3 = plan["rest_centre"]
	var mid: Vector3 = plan["mid"]
	if s >= 1.0:
		return Transform3D(rest_basis, rest - rest_basis * mid)
	var t := s * float(plan["seconds"])
	var v: Vector3 = plan["velocity"]
	var centre: Vector3 = (plan["start_centre"] as Vector3) + v * t + Vector3.DOWN * (0.5 * GRAVITY * t * t)
	# Arrive exactly on the rest spot whatever the arithmetic left over.
	centre = centre.lerp(rest, s * s * s)
	var turn := Quaternion(plan["axis"] as Vector3, TAU * float(plan["turns"]) * s)
	var basis := Basis(turn * Quaternion.IDENTITY.slerp(rest_basis.get_rotation_quaternion(), s))
	return Transform3D(basis, centre - basis * mid)


## A fragment: its voxels as a mesh, a box round its filled cells, no collision until it lands.
static func _fragment(model: VoxelModel, lo: Vector3, hi: Vector3, glass: bool) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Fragment"
	body.set_meta(&"fragment", true)
	body.collision_layer = 0
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = ((hi - lo) * 0.9).max(Vector3.ONE * 0.04)
	shape.shape = box
	shape.position = (lo + hi) / 2.0
	body.add_child(shape)
	if DisplayServer.get_name() != "headless":
		# The fragment keeps the see-through marks, which would leave a shard's mesh empty.
		model.set_clear_materials(PackedInt32Array())
		var mesh := MeshInstance3D.new()
		mesh.mesh = VoxGenerator.to_mesh(model)
		if glass:
			mesh.material_override = VoxelChunkedMesh.glass_material()
		body.add_child(mesh)
	return body


## Landed: solid rubble (glass stays out of everyone's way).
static func _land(body: Node3D, glass: bool) -> void:
	if not is_instance_valid(body):
		return
	(body as StaticBody3D).collision_layer = PhysicsLayers.DEBRIS if glass else PhysicsLayers.SOLID
	body.set_meta(&"landed", true)
