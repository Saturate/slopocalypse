class_name LandBiomes
extends GroundBiomes
## A generated map's woods, dry grass, rock and beaches (WorldLand's biome fields).

var land: WorldLand


func _init(map_land: WorldLand) -> void:
	land = map_land


func forest(x: float, z: float) -> float:
	return land.forest(x, z)


func dry(x: float, z: float) -> float:
	return land.dry(x, z)


func rock(x: float, z: float) -> float:
	return land.rock(x, z)


func sand(x: float, z: float) -> float:
	return land.sand(x, z)
