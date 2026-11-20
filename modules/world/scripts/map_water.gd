class_name MapWater
extends WaterBodies
## A generated map's ponds as water bodies (#472). A body's outline is the hull round its
## pond (good enough for drawing: the terrain hides the surface wherever the ground is above
## it), but water is only where the map's pond really is: a road cut or hollow inside the
## hull and below the level stays dry.

var land: WorldLand


func body_at(x: float, z: float) -> int:
	if land != null and is_nan(land.water_level(x, z)):
		return -1
	return super.body_at(x, z)
