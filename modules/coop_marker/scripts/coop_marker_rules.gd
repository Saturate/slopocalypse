class_name CoopMarkerRules
extends RefCounted
## Who gets a co-op marker and how strongly it shows (#447), pure so it can be tested alone.
##
## The marker is drawn through walls so you can always find your partner, including at night.
## It fades out where it is not needed:
## - up close: hidden within `hide_near_m`, full again `near_fade_m` further out;
## - plainly in view: nothing solid between your eye and them and within `in_view_m`, it
##   drops to `in_view_alpha` (kept above zero because "in view" says nothing about the
##   dark, where a clear line of sight still shows you nothing). Anyone else's body in the
##   way counts as solid: a partner behind a crowd is not plainly in view;
## - out of range: fades over the last `range_fade_m` before `range_m`, gone past it.

const REQUIRED := {"range_m": TYPE_FLOAT, "range_fade_m": TYPE_FLOAT, "hide_near_m": TYPE_FLOAT,
	"near_fade_m": TYPE_FLOAT, "in_view_m": TYPE_FLOAT, "in_view_alpha": TYPE_FLOAT, "fade_rate": TYPE_FLOAT,
	"aim_height_m": TYPE_FLOAT, "marker_height_m": TYPE_FLOAT, "marker_size": TYPE_FLOAT,
	"name_size": TYPE_FLOAT, "distance_size": TYPE_FLOAT, "colour": TYPE_STRING}


## Whether `node` is another co-op player worth a marker for `me`: in the `players` group,
## not `me`, not an enemy or civilian (they share the player scene and carry a `team` meta),
## and not lying dead. A player in a car is parked hidden where they got in; `riding` says
## they are, so they keep their marker (drawn over the car).
static func is_partner(node: Node, me: Node, riding := false) -> bool:
	if node == null or node == me or not node is Node3D:
		return false
	if not node.is_in_group(&"players") or node.is_in_group(&"enemies") or node.is_in_group(&"civilians"):
		return false
	if node.has_meta(&"team") or node.has_meta(&"civilian"):
		return false
	return not bool(node.get_meta(&"dead", false)) and (riding or (node as Node3D).is_visible_in_tree())


## How strongly the marker for a partner `distance` metres away shows, 0 to 1. `in_sight`:
## nothing solid between the eye and them.
static func alpha(distance: float, in_sight: bool, config: Dictionary) -> float:
	var range_m := float(config["range_m"])
	if distance > range_m:
		return 0.0
	var near := clampf((distance - float(config["hide_near_m"])) / maxf(float(config["near_fade_m"]), 0.001), 0.0, 1.0)
	var far := clampf((range_m - distance) / maxf(float(config["range_fade_m"]), 0.001), 0.0, 1.0)
	var view := float(config["in_view_alpha"]) if in_sight and distance <= float(config["in_view_m"]) else 1.0
	return near * far * view


## The distance shown under the name, in whole metres.
static func metres(distance: float) -> int:
	return roundi(maxf(distance, 0.0))


## Moves a shown alpha towards `target` at `rate` per second, frame-rate independent, so a
## partner stepping past a doorway does not make the marker blink.
static func ease_alpha(current: float, target: float, rate: float, delta: float) -> float:
	return lerpf(current, target, 1.0 - exp(-rate * delta))
