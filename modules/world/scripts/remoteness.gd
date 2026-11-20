class_name Remoteness
extends RefCounted
## How far a place is from people, 0 to 1 (#419): 0 near a settlement, rising with the
## distance travelled down the road from the nearest one and faster off the road beside it.
## Worked out from the map's data alone, so server and clients agree without sending it.
## Readers map it through their own curves (road wear and potholes so far). No autoloads.

const REQUIRED := {"settlements": TYPE_ARRAY, "reach": TYPE_FLOAT, "off_road": TYPE_FLOAT, "road_wear": TYPE_ARRAY, "road_potholes": TYPE_ARRAY}

var _places: Array[Vector2] = []
var _reach := 1.0
var _off_road := 1.0
var _wear := Vector2.ZERO
var _potholes := Vector2.ZERO


func _init(config: Dictionary) -> void:
	for s: Dictionary in config["settlements"]:
		_places.append(Vector2(float(s["along"]), float(s["radius"])))
	_reach = maxf(float(config["reach"]), 1.0)
	_off_road = float(config["off_road"])
	_wear = Vector2(float(config["road_wear"][0]), float(config["road_wear"][1]))
	_potholes = Vector2(float(config["road_potholes"][0]), float(config["road_potholes"][1]))


## At `along` metres down the road from its start and `off` metres beside the road's edge.
func at(along: float, off: float = 0.0) -> float:
	var nearest := INF
	for p in _places:
		nearest = minf(nearest, maxf(absf(along - p.x) - p.y, 0.0))
	if nearest == INF:
		nearest = 0.0
	return clampf((nearest + _off_road * maxf(off, 0.0)) / _reach, 0.0, 1.0)


## A road piece's wear (0 to 1) and how many potholes it starts with, at `along`.
func road_wear(along: float) -> float:
	return lerpf(_wear.x, _wear.y, at(along))


func road_potholes(along: float) -> int:
	return roundi(lerpf(_potholes.x, _potholes.y, at(along)))
