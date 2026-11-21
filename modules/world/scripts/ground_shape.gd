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
