class_name LooseChunks
extends RefCounted
## Client-only: a broken piece of building comes loose as chunks made of its own voxels.
## Each chunk is a small rigid body thrown out (or just let go, for a piece losing its
## support): it tumbles, bounces, lands, lies there a while, then sinks into the ground. They
## live on each client alone and touch nothing that matters: they're on the `DEBRIS` layer,
## which bodies walk through and bullets and eyes ignore.

const CONFIG := "res://modules/missions/data/missions.json"

## Live chunks, oldest first, so the cap drops the oldest.
static var _live: Array[RigidBody3D] = []
static var _cfg: Dictionary = {}


static func config() -> Dictionary:
	if _cfg.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
		var buildings: Dictionary = (data as Dictionary).get("buildings", {}) if data is Dictionary else {}
		_cfg = buildings.get("chunks", {}) as Dictionary
	return _cfg


## Splits `box` (local to `building`) of `model` into chunks about `size` across and lets them
## go from where they are, pushed along `push` (world, metres per second) with some scatter.
## Returns how many it made.
static func spawn(building: Node3D, model: VoxelModel, box: AABB, push: Vector3, rng: RandomNumberGenerator) -> int:
	if building == null or not building.is_inside_tree() or model == null:
		return 0
	var cfg := config()
	var size := float(cfg.get("size", 0.45))
	var per_piece := int(cfg.get("max_per_piece", 12))
	# Coarser split when a piece would make too many: halve the most-split side until it fits.
	var counts := Vector3i((box.size / size).ceil().max(Vector3.ONE))
	while counts.x * counts.y * counts.z > per_piece:
		if counts.x >= counts.y and counts.x >= counts.z:
			counts.x = maxi(1, ceili(counts.x / 2.0))
		elif counts.y >= counts.z:
			counts.y = maxi(1, ceili(counts.y / 2.0))
		else:
			counts.z = maxi(1, ceili(counts.z / 2.0))
	var step := box.size / Vector3(counts)
	var made := 0
	var parent := building.get_parent()
	for ix in counts.x:
		for iy in counts.y:
			for iz in counts.z:
				var lo := box.position + step * Vector3(ix, iy, iz)
				var copy: Dictionary = model.copy_box(lo, lo + step)
				if copy.is_empty() or (copy["model"] as VoxelModel).voxel_count() == 0:
					continue
				var body := _chunk(copy["model"], step, cfg)
				parent.add_child(body)
				var centre_local: Vector3 = (copy["offset"] as Vector3)
				body.global_transform = building.global_transform * Transform3D(Basis.IDENTITY, centre_local)
				var scatter := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.0, 1.0), rng.randf_range(-1.0, 1.0)) * float(cfg.get("scatter", 1.5))
				body.linear_velocity = push + scatter
				body.angular_velocity = Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * float(cfg.get("spin", 4.0))
				_track(body, int(cfg.get("max_live", 80)))
				made += 1
	return made


static func live_count() -> int:
	_live.assign(_live.filter(func(b: Variant) -> bool: return is_instance_valid(b)))
	return _live.size()


## One chunk: its voxels as a mesh, a box shape round them, light enough to bounce.
static func _chunk(model: VoxelModel, extent: Vector3, cfg: Dictionary) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = "Chunk"
	body.collision_layer = PhysicsLayers.DEBRIS
	body.collision_mask = PhysicsLayers.SOLID
	body.mass = maxf(1.0, extent.x * extent.y * extent.z * float(cfg.get("kg_per_m3", 600.0)))
	var mesh := MeshInstance3D.new()
	mesh.mesh = VoxGenerator.to_mesh(model)
	body.add_child(mesh)
	var cells := Vector3(model.cells()) * model.voxel_size()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = (cells * 0.9).max(Vector3.ONE * 0.05)
	shape.shape = box
	# The model stands on its origin with x and z centred: its middle is half its height up.
	shape.position = Vector3(0.0, cells.y / 2.0, 0.0)
	body.add_child(shape)
	var life := float(cfg.get("seconds", 6.0))
	var sink := float(cfg.get("sink_seconds", 1.5))
	body.ready.connect(func() -> void:
		body.get_tree().create_timer(life).timeout.connect(func() -> void:
			if not is_instance_valid(body):
				return
			body.freeze = true
			var tween := body.create_tween()
			tween.tween_property(body, "global_position:y", body.global_position.y - cells.y - 0.3, sink)
			tween.tween_callback(body.queue_free)))
	return body


static func _track(body: RigidBody3D, cap: int) -> void:
	_live.append(body)
	_live.assign(_live.filter(func(b: Variant) -> bool: return is_instance_valid(b)))
	while _live.size() > cap:
		var oldest: RigidBody3D = _live.pop_front()
		oldest.queue_free()
