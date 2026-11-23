class_name CampPlan
extends RefCounted
## What the players' camp is built of (camp.json) on its layout (CampLayout, the world's): a
## wooden fence (VoxFence) along each of the layout's fence runs, planks outward, the
## corners and gateposts taller; the walk-in hut (VoxShed) on its spot; and the yards of
## packed dirt. Pure; no autoloads.

const CONFIG := "res://modules/camp/data/camp.json"
const REQUIRED := {"sink": TYPE_FLOAT, "fence": TYPE_DICTIONARY, "hut": TYPE_DICTIONARY, "yard": TYPE_ARRAY}


## Every piece as {kind ("fence" or "hut"), generator, params, transform}. The back and the
## gate side's runs carry the tall corner posts; the two sides are cut short by a corner
## post at each end so no two posts stand in each other.
static func plan(camp: CampLayout, cfg: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var sink := Vector3.DOWN * float(cfg["sink"])
	var runs := camp.fence_runs()
	for i in runs.size():
		var a := runs[i][0]
		var b := runs[i][1]
		# Runs 1 and 2 are the sides (see CampLayout.fence_runs).
		var side := i == 1 or i == 2
		if side:
			var along := (b - a).normalized()
			a += along * VoxFence.END_POST
			b -= along * VoxFence.END_POST
		var params: Dictionary = (cfg["fence"] as Dictionary).duplicate()
		params["seed"] = i + 1
		params["length"] = a.distance_to(b)
		params["tall_ends"] = 0 if side else 1
		out.append({"kind": "fence", "generator": "VoxFence", "params": params, "transform": _run_transform(camp, a, b).translated(sink)})
	var hut: Dictionary = (cfg["hut"] as Dictionary).duplicate()
	hut["width"] = camp.hut_size.x
	hut["depth"] = camp.hut_size.y
	out.append({"kind": "hut", "generator": "VoxShed", "params": hut, "transform": camp.spot("hut").translated(sink)})
	return out


## A fence run from `a` to `b` stood with its x along the run and its planks (-z) facing out
## of the camp.
static func _run_transform(camp: CampLayout, a: Vector3, b: Vector3) -> Transform3D:
	var x := (b - a).normalized()
	var mid := (a + b) / 2.0
	# x cross up is the basis' z; it must point into the camp, so the planks (-z) face out.
	var inward := Vector3(camp.centre.x - mid.x, 0.0, camp.centre.z - mid.z)
	if x.cross(Vector3.UP).dot(inward) < 0.0:
		x = -x
	return Transform3D(Basis(x, Vector3.UP, x.cross(Vector3.UP)), mid)


## The yards (camp.json `yard`) as SceneryScatter's `set_yards_for` takes them: {from, to (x,
## z: the middles of its two ends), width, level, rect}, each cut to the pad.
static func yards(camp: CampLayout, cfg: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r: Array in cfg["yard"]:
		var a := camp.point(Vector2(float(r[0]), float(r[1])))
		var b := camp.point(Vector2(float(r[2]), float(r[3])))
		var rect := Rect2(Vector2(a.x, a.z), Vector2.ZERO).expand(Vector2(b.x, b.z)).intersection(camp.pad)
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		var along_x := rect.size.x >= rect.size.y
		var mid := rect.get_center()
		var from := Vector2(rect.position.x, mid.y) if along_x else Vector2(mid.x, rect.position.y)
		var to := Vector2(rect.end.x, mid.y) if along_x else Vector2(mid.x, rect.end.y)
		out.append({"from": from, "to": to, "width": rect.size.y if along_x else rect.size.x, "level": camp.centre.y, "rect": rect})
	return out
