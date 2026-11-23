class_name Ladders
extends RefCounted
## Every ladder standing in the world, for bodies that climb them (PlayerController). Whatever
## stands a ladder up adds it here and removes it when it goes. A ladder is the box someone
## climbing it is in (its frame, half its size) and the way into it, the direction a climber
## faces to go up. Asked every physics tick per body, so it is a plain list, not physics.

## Each {frame: Transform3D (the box's centre, turned with the ladder), half: Vector3,
## into: Vector3 (unit, level), owner: Object}.
static var _all: Array[Dictionary] = []


static func add(owner: Object, frame: Transform3D, half: Vector3, into: Vector3) -> void:
	_all.append({"frame": frame, "half": half, "into": Vector3(into.x, 0.0, into.z).normalized(), "owner": owner})


static func remove(owner: Object) -> void:
	_all = _all.filter(func(l: Dictionary) -> bool: return l["owner"] != owner)


static func count() -> int:
	return _all.size()


## The ladder a body standing at `feet`, `height` tall and `radius` round, is on: its entry
## with `top` (the world height its climb ends at) added; empty when on none.
static func at(feet: Vector3, height: float, radius: float) -> Dictionary:
	for l in _all:
		var frame: Transform3D = l["frame"]
		var half: Vector3 = l["half"]
		# Far ladders cost one distance check.
		if feet.distance_squared_to(frame.origin) > (half.length() + height + radius) ** 2:
			continue
		var local := frame.affine_inverse() * feet
		if absf(local.x) > half.x + radius or absf(local.z) > half.z + radius:
			continue
		if local.y > half.y or local.y + height < -half.y:
			continue
		var out := l.duplicate()
		out["top"] = (frame * Vector3(0.0, half.y, 0.0)).y
		return out
	return {}
