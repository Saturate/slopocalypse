class_name GroundShape
extends RefCounted
## The land the voxel terrain and the scenery are built from: its height, extent, water and
## where roads are. The generated map (MapShape) answers these. Runs without autoloads.

## Ponds, lakes and flooded craters.
var water: WaterBodies


## Height of the ground at (x, z), water beds included.
func height_at(_x: float, _z: float) -> float:
	return 0.0


## The world's footprint on the ground (x, z).
func extent() -> Rect2:
	return Rect2()


func in_water(x: float, z: float) -> bool:
	return water != null and water.body_at(x, z) >= 0


## Whether (x, z) is on a road or within `margin` metres of its edge.
func near_road(_x: float, _z: float, _margin: float) -> bool:
	return false


## Metres from (x, z) to the nearest road's edge: 0 on a road, INF with no road near.
func road_edge_distance(_x: float, _z: float) -> float:
	return INF


## Whether (x, z) is on a site's levelled pad (a farm, a water tower...), kept free of
## trees and rocks.
func on_site(_x: float, _z: float) -> bool:
	return false


## Whether (x, z) is on a site's pad or within `clearance` of it (metres by site kind, with a
## `default`), close enough to keep trees and rocks off so they don't crowd what stands there.
func near_site(_x: float, _z: float, _clearance: Dictionary) -> bool:
	return false


## Whether (x, z) is within `high` metres of a high-voltage line or `low` of a pole line:
## ground kept free of trees.
func near_power(_x: float, _z: float, _high: float, _low: float) -> bool:
	return false


## Whether (x, z) is on the players' camp pad or within `margin` metres of it: ground kept
## free of trees and rocks.
func near_camp(_x: float, _z: float, _margin: float) -> bool:
	return false
