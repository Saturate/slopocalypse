class_name WireCurve
extends RefCounted
## Where a hanging wire runs: pure functions over two attach points, no nodes.
##
## The curve is a parabola under the straight line between the ends. `sag` is how far the
## middle of the span hangs below that line, in metres; a kind's data gives it as a share of
## the span's length (`sag_for`). For the shallow sags of real lines a parabola is within a
## few centimetres of the true catenary and has a lowest point in closed form.


## How far the middle of a span from `a` to `b` hangs below the straight line, for a kind
## whose `ratio` is the dip as a share of the span's length.
static func sag_for(a: Vector3, b: Vector3, ratio: float) -> float:
	return maxf(ratio, 0.0) * a.distance_to(b)


## The point a share `t` (0 at `a`, 1 at `b`) along the span. Across the ground it runs
## straight from end to end; only the height bends.
static func point_at(a: Vector3, b: Vector3, sag: float, t: float) -> Vector3:
	if t <= 0.0:
		return a
	if t >= 1.0:
		return b
	var p := a.lerp(b, t)
	p.y -= 4.0 * sag * t * (1.0 - t)
	return p


## `segments` + 1 points from share `t0` to `t1` of the span, evenly spaced along it. The
## ends of the whole span come out exactly as the attach points.
static func points_between(a: Vector3, b: Vector3, sag: float, t0: float, t1: float, segments: int) -> PackedVector3Array:
	var n := maxi(segments, 1)
	var out := PackedVector3Array()
	out.resize(n + 1)
	for i in n + 1:
		out[i] = point_at(a, b, sag, lerpf(t0, t1, float(i) / float(n)))
	return out


static func points(a: Vector3, b: Vector3, sag: float, segments: int) -> PackedVector3Array:
	return points_between(a, b, sag, 0.0, 1.0, segments)


## Share along the span of its lowest point: the middle on a level span, nearer the lower
## end when the ends differ in height, and an end itself when the drop outweighs the sag.
static func lowest_t(a: Vector3, b: Vector3, sag: float) -> float:
	var rise := b.y - a.y
	if sag <= 0.0:
		return 0.0 if rise >= 0.0 else 1.0
	# Where the height's slope, rise - 4·sag·(1 - 2t), is zero.
	return clampf(0.5 - rise / (8.0 * sag), 0.0, 1.0)


static func lowest_point(a: Vector3, b: Vector3, sag: float) -> Vector3:
	return point_at(a, b, sag, lowest_t(a, b, sag))


## Segments for a stretch `length` metres long when each should be about `segment_length`,
## never fewer than `least`.
static func segment_count(length: float, segment_length: float, least: int = 1) -> int:
	if segment_length <= 0.0:
		return maxi(least, 1)
	return maxi(ceili(length / segment_length - 0.001), maxi(least, 1))


## Which detail step a wire `distance` metres from the camera is drawn at: the first whose
## `until` it is inside; the last step past all of them. `steps` is the data's `lod` list.
static func step_at(distance: float, steps: Array) -> int:
	for i in steps.size():
		var step: Dictionary = steps[i]
		if distance < float(step.get("until", INF)):
			return i
	return maxi(steps.size() - 1, 0)


## Segments for a stretch at a detail step: the full-detail count scaled down by the step's
## `detail` (1 = every segment), never fewer than `least`.
static func segments_at(length: float, segment_length: float, distance: float, steps: Array, least: int = 2) -> int:
	var detail := 1.0
	if not steps.is_empty():
		detail = float((steps[step_at(distance, steps)] as Dictionary).get("detail", 1.0))
	if detail <= 0.0:
		return maxi(least, 1)
	return segment_count(length, segment_length / detail, least)
