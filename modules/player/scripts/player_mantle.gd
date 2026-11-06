class_name PlayerMantle
extends RefCounted
## Finds what the player can climb (mantle onto a ledge) or vault (over a low, thin
## obstacle and land on the far side) directly in front of them.


## Returns the standing point on top of a ledge, or null when there is nothing to climb.
static func find_ledge(body: CharacterBody3D, cfg: Dictionary) -> Variant:
	var top: Variant = _top_ahead(body, cfg, float(cfg["mantle_max_height"]))
	if not top is Vector3:
		return null
	var point: Vector3 = top
	if not _room_to_stand(body, cfg, point):
		return null
	return point + Vector3.UP * 0.02


## Returns {"top": Vector3, "landing": Vector3} for a low, thin obstacle with clear ground
## beyond it, or null.
static func find_vault(body: CharacterBody3D, cfg: Dictionary) -> Variant:
	var top: Variant = _top_ahead(body, cfg, float(cfg["vault_max_height"]))
	if not top is Vector3:
		return null
	var top_point: Vector3 = top
	var space := body.get_world_3d().direct_space_state
	var feet := body.global_position
	var forward := _flat_forward(body)
	var exclude: Array[RID] = [body.get_rid()]
	var max_depth: float = cfg["vault_max_depth"]
	var radius: float = cfg["radius"]
	# Walk forward over the top until the surface drops away: that is the far edge.
	var step := 0.15
	var travelled := step
	while travelled <= max_depth + radius * 2.0 + 0.6:
		var probe := top_point + forward * travelled
		var ray := PhysicsRayQueryParameters3D.create(probe + Vector3.UP * 0.3, probe + Vector3.DOWN * (top_point.y - feet.y + 0.8), body.collision_mask, exclude)
		var hit := space.intersect_ray(ray)
		if hit.is_empty():
			return null
		var ground: Vector3 = hit["position"]
		if ground.y < top_point.y - 0.3:
			# Obstacle too deep to clear in one bound: climb it instead.
			if travelled - step > max_depth:
				return null
			# Land a body's width past the edge so the capsule clears the obstacle.
			var landing_probe := top_point + forward * (travelled + radius + 0.1)
			var land_ray := PhysicsRayQueryParameters3D.create(landing_probe + Vector3.UP * 0.3, landing_probe + Vector3.DOWN * (top_point.y - feet.y + 0.8), body.collision_mask, exclude)
			var land_hit := space.intersect_ray(land_ray)
			if land_hit.is_empty():
				return null
			var landing: Vector3 = land_hit["position"]
			if absf(landing.y - feet.y) > 0.6 or not _room_to_stand(body, cfg, landing):
				return null
			return {"top": top_point, "landing": landing + Vector3.UP * 0.02}
		travelled += step
	return null


## Something blocks the way at knee height and its walkable top is within `max_height`.
static func _top_ahead(body: CharacterBody3D, cfg: Dictionary, max_height: float) -> Variant:
	var space := body.get_world_3d().direct_space_state
	var feet := body.global_position
	var forward := _flat_forward(body)
	var radius: float = cfg["radius"]
	var reach: float = cfg["mantle_reach"]
	var min_height: float = cfg["mantle_min_height"]
	var exclude: Array[RID] = [body.get_rid()]

	var knee := feet + Vector3.UP * min_height
	var wall := PhysicsRayQueryParameters3D.create(knee, knee + forward * (radius + reach), body.collision_mask, exclude)
	var wall_hit := space.intersect_ray(wall)
	if wall_hit.is_empty():
		return null
	# Probe just past the wall face, so thin obstacles are found too.
	var face_distance := (Vector3(wall_hit["position"]) - knee).length()
	var probe := feet + forward * (face_distance + 0.1)
	var down := PhysicsRayQueryParameters3D.create(probe + Vector3.UP * (max_height + 0.2), probe + Vector3.UP * min_height, body.collision_mask, exclude)
	var top := space.intersect_ray(down)
	if top.is_empty():
		return null
	var top_point: Vector3 = top["position"]
	var normal: Vector3 = top["normal"]
	var height := top_point.y - feet.y
	if height < min_height or height > max_height or normal.dot(Vector3.UP) < 0.7:
		return null
	return top_point


static func _room_to_stand(body: CharacterBody3D, cfg: Dictionary, feet_at: Vector3) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = cfg["radius"]
	capsule.height = cfg["stand_height"]
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, feet_at + Vector3.UP * (capsule.height / 2.0 + 0.05))
	query.collision_mask = body.collision_mask
	query.exclude = [body.get_rid()]
	return body.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


static func _flat_forward(body: Node3D) -> Vector3:
	var forward := -body.global_transform.basis.z
	forward.y = 0.0
	return forward.normalized()
