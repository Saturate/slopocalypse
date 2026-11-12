class_name LooseChunks
extends RefCounted
## A broken piece of building comes loose as chunks made of its own voxels, and the chunks
## become its rubble. The split is fixed by the piece and each chunk's throw comes from a seed,
## so the server and every client start the same chunks moving the same way. Flying, they're
## on the `DEBRIS` layer (they land on the ground, the building and each other; bodies walk
## through, bullets and eyes ignore them). The server lets them come to rest, then says where
## each one lies; everyone freezes it there, solid, so the rubble is cover you can climb and
## the same for everyone. A late joiner places them straight where they lie.

const CONFIG := "res://modules/missions/data/missions.json"

static var _cfg: Dictionary = {}


static func config() -> Dictionary:
	if _cfg.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
		var buildings: Dictionary = (data as Dictionary).get("buildings", {}) if data is Dictionary else {}
		_cfg = buildings.get("chunks", {}) as Dictionary
	return _cfg


## The chunks `box` splits into, about `size` across (the data's when 0), at most
## `per_piece` (likewise): the same boxes for the same piece everywhere.
static func boxes(box: AABB, size: float = 0.0, per_piece: int = 0) -> Array[AABB]:
	var cfg := config()
	if size <= 0.0:
		size = float(cfg.get("size", 0.45))
	if per_piece <= 0:
		per_piece = int(cfg.get("max_per_piece", 10))
	var counts := Vector3i((box.size / size).ceil().max(Vector3.ONE))
	# Coarser when a piece would make too many: halve the most-split side until it fits.
	while counts.x * counts.y * counts.z > per_piece:
		if counts.x >= counts.y and counts.x >= counts.z:
			counts.x = maxi(1, ceili(counts.x / 2.0))
		elif counts.y >= counts.z:
			counts.y = maxi(1, ceili(counts.y / 2.0))
		else:
			counts.z = maxi(1, ceili(counts.z / 2.0))
	var step := box.size / Vector3(counts)
	var out: Array[AABB] = []
	for ix in counts.x:
		for iy in counts.y:
			for iz in counts.z:
				out.append(AABB(box.position + step * Vector3(ix, iy, iz), step))
	return out


## Lets the chunks of piece `seg` (its voxels in `box` of `model`, local to `building`) go,
## pushed along `push` (local, metres per second) with seeded scatter. Returns `{index: body}`
## for the chunks that have voxels.
static func spawn(building: Node3D, model: VoxelModel, seg: int, box: AABB, push: Vector3, seed: int, parts: Array[AABB] = [], glass := false) -> Dictionary:
	var out := {}
	if building == null or not building.is_inside_tree() or model == null:
		return out
	var cfg := config()
	if parts.is_empty():
		parts = boxes(box)
	for k in parts.size():
		var body := make(building, model, parts[k], glass)
		if body == null:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([seed, seg, k])
		var scatter := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.0, 1.0), rng.randf_range(-1.0, 1.0)) * float(cfg.get("scatter", 1.5))
		body.linear_velocity = building.global_transform.basis * (push + scatter)
		body.angular_velocity = Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * float(cfg.get("spin", 4.0))
		out[k] = body
	return out


## One chunk of `part` (local to `building`) of `model`, where it sits in the building, flying;
## null when there's nothing there. `glass`: a shard, drawn see-through like the pane it was.
static func make(building: Node3D, model: VoxelModel, part: AABB, glass := false) -> RigidBody3D:
	var copy: Dictionary = model.copy_box(part.position, part.end)
	if copy.is_empty() or (copy["model"] as VoxelModel).voxel_count() == 0:
		return null
	var chunk_model: VoxelModel = copy["model"]
	# The copy keeps the see-through marks, which would leave a shard's normal mesh empty.
	chunk_model.set_clear_materials(PackedInt32Array())
	var body := RigidBody3D.new()
	body.name = "Chunk"
	body.collision_layer = PhysicsLayers.DEBRIS
	body.collision_mask = PhysicsLayers.SOLID | PhysicsLayers.DEBRIS
	body.mass = maxf(1.0, part.size.x * part.size.y * part.size.z * float(config().get("kg_per_m3", 600.0)))
	var cells := Vector3(chunk_model.cells()) * chunk_model.voxel_size()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = (cells * 0.9).max(Vector3.ONE * 0.05)
	shape.shape = box
	# The model stands on its origin with x and z centred: its middle is half its height up.
	shape.position = Vector3(0.0, cells.y / 2.0, 0.0)
	body.add_child(shape)
	if DisplayServer.get_name() != "headless":
		var mesh := MeshInstance3D.new()
		mesh.mesh = VoxGenerator.to_mesh(chunk_model)
		if glass:
			mesh.material_override = VoxelChunkedMesh.glass_material()
		body.add_child(mesh)
	building.get_parent().add_child(body)
	body.global_transform = building.global_transform * Transform3D(Basis.IDENTITY, copy["offset"] as Vector3)
	return body


## Freezes `body` where it lies (or, given `to`, eases it there first): rubble, solid unless
## `solid` is false (glass shards lie there but stop nothing).
static func settle(body: RigidBody3D, to: Variant = null, solid := true) -> void:
	if not is_instance_valid(body):
		return
	body.freeze = true
	body.collision_layer = PhysicsLayers.SOLID if solid else PhysicsLayers.DEBRIS
	body.collision_mask = 0
	if to is Transform3D and body.is_inside_tree():
		var tween := body.create_tween()
		tween.tween_property(body, "global_transform", to as Transform3D, float(config().get("ease_seconds", 0.35)))
