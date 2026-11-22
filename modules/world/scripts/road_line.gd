class_name RoadLine
extends RefCounted
## One generated road (RoadNetwork) read by distance along it (#472): where it is, which way
## it runs and how high it is at any metre, and where a point lies against it. Road surfaces
## are bent along it and craters cut into them through it. Pure; no autoloads.

var kind := ""
var width := 0.0
var points := PackedVector2Array()
var heights := PackedFloat32Array()
## Metres along the road at each point.
var along := PackedFloat32Array()
## The box (x, z) its middle line stays in.
var _bounds := Rect2()


func _init(road: Dictionary) -> void:
	kind = str(road["kind"])
	width = float(road["width"])
	points = road["points"]
	heights = road["heights"]
	along.resize(points.size())
	for k in range(1, points.size()):
		along[k] = along[k - 1] + points[k].distance_to(points[k - 1])
	if not points.is_empty():
		_bounds = Rect2(points[0], Vector2.ZERO)
		for p in points:
			_bounds = _bounds.expand(p)


## The box (x, z) its middle line stays in.
func bounds() -> Rect2:
	return _bounds


func length() -> float:
	return along[along.size() - 1] if not along.is_empty() else 0.0


## The segment `s` metres along lies on, and how far along it (0 to 1).
func _segment(s: float) -> Vector2:
	var n := points.size()
	if n < 2:
		return Vector2.ZERO
	s = clampf(s, 0.0, length())
	var lo := 0
	var hi := n - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if along[mid] <= s:
			lo = mid
		else:
			hi = mid
	var run := maxf(along[hi] - along[lo], 0.0001)
	return Vector2(lo, (s - along[lo]) / run)


## The road's middle `s` metres along (x, z).
func point_at(s: float) -> Vector2:
	var seg := _segment(s)
	var k := int(seg.x)
	return points[k].lerp(points[mini(k + 1, points.size() - 1)], seg.y)


func height_at(s: float) -> float:
	var seg := _segment(s)
	var k := int(seg.x)
	return lerpf(heights[k], heights[mini(k + 1, heights.size() - 1)], seg.y)


## Which way the road runs `s` metres along (unit, x and z).
func direction_at(s: float) -> Vector2:
	var k := int(_segment(s).x)
	var d := points[mini(k + 1, points.size() - 1)] - points[k]
	return d.normalized() if d.length() > 0.0001 else Vector2(0.0, -1.0)


## Across the road at `s`: to the right of its direction (x, z).
func across_at(s: float) -> Vector2:
	var d := direction_at(s)
	return Vector2(-d.y, d.x)


## Where `p` lies against the road between `from` and `to` metres along: Vector2(metres
## along, metres across, + to the right), from the nearest point of that stretch.
func locate(p: Vector2, from: float, to: float) -> Vector2:
	var best := Vector2(from, INF)
	var best_d := INF
	var first := int(_segment(from).x)
	var last := mini(int(_segment(to).x) + 1, points.size() - 1)
	for k in range(first, last):
		var a := points[k]
		var ab := points[k + 1] - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var on := a + ab * t
		var d := p.distance_to(on)
		if d < best_d:
			best_d = d
			var right := Vector2(-ab.y, ab.x).normalized()
			best = Vector2(along[k] + ab.length() * t, (p - on).dot(right))
	return best
