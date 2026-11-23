class_name SuppressionLevel
extends RefCounted
## One player's suppression, 0 to 1: each near miss adds `per_near_miss`, it falls by
## `decay_per_second`, and it never goes past 1. Pure rules, the same on the server (which
## decides it) and the owning client (which follows it between the server's updates).

var value := 0.0
var per_near_miss := 0.1
var decay_per_second := 0.25


static func from_config(config: Dictionary) -> SuppressionLevel:
	var level := SuppressionLevel.new()
	level.per_near_miss = float(config.get("per_near_miss", level.per_near_miss))
	level.decay_per_second = float(config.get("decay_per_second", level.decay_per_second))
	return level


func add_near_miss() -> void:
	value = minf(value + per_near_miss, 1.0)


func tick(delta: float) -> void:
	value = maxf(value - decay_per_second * delta, 0.0)


func reset() -> void:
	value = 0.0


## Closest distance from `point` to the segment `a`..`b`: how close a round's path came.
## The same test soldiers use for their own near misses.
static func distance_to_segment(point: Vector3, a: Vector3, b: Vector3) -> float:
	return point.distance_to(closest_on_segment(point, a, b))


static func closest_on_segment(point: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var ab := b - a
	var t := clampf((point - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return a + ab * t
