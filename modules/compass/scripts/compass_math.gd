class_name CompassMath
extends RefCounted
## The compass strip's maths, pure so it can be tested on its own (#455). Degrees throughout;
## north is -Z (the world's forward) and east +X, so bearings go clockwise seen from above.


## Bearing from `from` to `to` on the ground, 0 to 360.
static func bearing(from: Vector3, to: Vector3) -> float:
	var d := to - from
	return fposmod(rad_to_deg(atan2(d.x, -d.z)), 360.0)


## Which way a camera with this basis looks, on the ground, 0 to 360.
static func heading(basis: Basis) -> float:
	var forward := -basis.z
	return fposmod(rad_to_deg(atan2(forward.x, -forward.z)), 360.0)


## Where `bearing_deg` lands on a strip showing `span` degrees centred on `heading_deg`:
## {x: -1 (left edge) to 1 (right edge), clamped: true when it is past an edge and sticks
## to it}. Straight behind wraps to -180 degrees, so it sticks to the left edge.
static func place(bearing_deg: float, heading_deg: float, span: float) -> Dictionary:
	var off := wrapf(bearing_deg - heading_deg, -180.0, 180.0)
	var x := off / (span * 0.5)
	if absf(x) <= 1.0:
		return {"x": x, "clamped": false}
	return {"x": signf(x), "clamped": true}


## How visible a marker this far away is: 0 within `near` metres (you can see the thing
## itself), fully shown from `near + band` on.
static func fade(distance: float, near: float, band: float) -> float:
	return clampf((distance - near) / maxf(band, 0.001), 0.0, 1.0)


## "Ana Lopez" -> "AL": the first letter of each word, for names that would overlap.
static func initials(full_name: String) -> String:
	var out := ""
	for word in full_name.strip_edges().split(" ", false):
		out += word.left(1).to_upper()
	return out


## Marker positions (pixels along the strip, any order) moved apart just enough that no two
## are closer than `gap`, kept within `low` to `high`: each keeps its place in the order and
## stays as near its own spot as the others allow. Markers stuck to an edge then line up
## inward from it instead of covering each other.
static func spread(xs: Array[float], gap: float, low: float, high: float) -> Array[float]:
	var order: Array = range(xs.size())
	order.sort_custom(func(a: int, b: int) -> bool: return xs[a] < xs[b])
	var placed: Array[float] = []
	for i: int in order:
		placed.append(clampf(xs[i], low, high))
	# Left to right pushes crowded markers right; right to left then pulls any pushed past the
	# far end back in, pushing their neighbours left.
	for k in range(1, placed.size()):
		placed[k] = maxf(placed[k], placed[k - 1] + gap)
	if not placed.is_empty():
		placed[-1] = minf(placed[-1], high)
	for k in range(placed.size() - 2, -1, -1):
		placed[k] = minf(placed[k], placed[k + 1] - gap)
	var out: Array[float] = []
	out.resize(xs.size())
	for k in order.size():
		# More markers than fit: the leftmost ones share the left end.
		out[int(order[k])] = maxf(placed[k], low)
	return out


## For marker positions along the strip (-1 to 1), which ones sit within `gap` of another.
static func crowded(xs: PackedFloat32Array, gap: float) -> Array[bool]:
	var out: Array[bool] = []
	for i in xs.size():
		var near := false
		for j in xs.size():
			if i != j and absf(xs[i] - xs[j]) < gap:
				near = true
				break
		out.append(near)
	return out
