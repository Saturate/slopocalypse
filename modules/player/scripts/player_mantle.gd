class_name PlayerMantle
extends RefCounted
## Finds a ledge in front of the player that they can climb onto: something blocks the
## way at knee height, its top is within reach, and there is room to stand up there.


## Returns the standing point on top of the ledge, or null when there is nothing to climb.
static func find_ledge(body: CharacterBody3D, cfg: Dictionary) -> Variant:
	var space := body.get_world_3d().direct_space_state
	var feet := body.global_position
	var forward := -body.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var radius: float = cfg["radius"]
	var reach: float = cfg["mantle_reach"]
	var min_height: float = cfg["mantle_min_height"]
	var max_height: float = cfg["mantle_max_height"]
	var exclude: Array[RID] = [body.get_rid()]

	# 1. Something solid in front at knee height, otherwise there is nothing to climb.
	var knee := feet + Vector3.UP * min_height
	var wall := PhysicsRayQueryParameters3D.create(knee, knee + forward * (radius + reach), body.collision_mask, exclude)
	if space.intersect_ray(wall).is_empty():
		return null

	# 2. Look down from above the reach point for the top surface.
	var probe := feet + forward * (radius + reach * 0.75)
	var down := PhysicsRayQueryParameters3D.create(probe + Vector3.UP * (max_height + 0.2), probe + Vector3.UP * min_height, body.collision_mask, exclude)
	var top := space.intersect_ray(down)
	if top.is_empty():
		return null
	var top_point: Vector3 = top["position"]
	var normal: Vector3 = top["normal"]
	var height := top_point.y - feet.y
	if height < min_height or height > max_height or normal.dot(Vector3.UP) < 0.7:
		return null

	# 3. Room to stand on top: the standing capsule must not overlap anything there.
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = cfg["stand_height"]
	var shape_query := PhysicsShapeQueryParameters3D.new()
	shape_query.shape = capsule
	shape_query.transform = Transform3D(Basis.IDENTITY, top_point + Vector3.UP * (capsule.height / 2.0 + 0.05))
	shape_query.collision_mask = body.collision_mask
	shape_query.exclude = exclude
	if not space.intersect_shape(shape_query, 1).is_empty():
		return null
	return top_point + Vector3.UP * 0.02
