class_name RoadStages
extends RefCounted
## How the land changes with distance down the road: a list of stages, each `{at: metres,
## <field>: value ...}`, interpolated between neighbours. Fields used today: forest, dry,
## rock (biome weights) and hills (terrain height multiplier).

var _stages: Array[Dictionary] = []


func _init(stages: Array = []) -> void:
	for s: Variant in stages:
		if s is Dictionary:
			_stages.append(s)
	_stages.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("at", 0.0)) < float(b.get("at", 0.0)))


## The value of `field` at `distance` metres down the road; `fallback` with no stages.
func value(field: String, distance: float, fallback: float = 1.0) -> float:
	if _stages.is_empty():
		return fallback
	var first: Dictionary = _stages[0]
	if distance <= float(first.get("at", 0.0)):
		return float(first.get(field, fallback))
	for i in range(1, _stages.size()):
		var b: Dictionary = _stages[i]
		if distance <= float(b.get("at", 0.0)):
			var a: Dictionary = _stages[i - 1]
			var t := inverse_lerp(float(a.get("at", 0.0)), float(b.get("at", 0.0)), distance)
			return lerpf(float(a.get(field, fallback)), float(b.get(field, fallback)), smoothstep(0.0, 1.0, t))
	return float(_stages[-1].get(field, fallback))
