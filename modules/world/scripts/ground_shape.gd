class_name GroundShape
extends RefCounted
## The land the voxel terrain and the scenery are built from: its height, extent, water and
## where roads are. The strip (TerrainHeights) and the generated map (MapShape) answer the
## same calls (#472). Runs without autoloads.

## The strip's single road and start tunnel; null and empty on a generated map.
var road: RoadPath
var start: Dictionary = {}
var stages: RoadStages
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


func has_tunnel() -> bool:
	return false


func in_tunnel(_x: float, _z: float, _margin: float = 0.0) -> bool:
	return false


## Whether (x, z) is on a road or within `margin` metres of its edge.
func near_road(_x: float, _z: float, _margin: float) -> bool:
	return false


## Whether (x, z) is on a site's levelled pad (a farm, a water tower...), kept free of
## trees and rocks.
func on_site(_x: float, _z: float) -> bool:
	return false


func z_max() -> float:
	return extent().end.y


func z_min() -> float:
	return extent().position.y
