class_name GroundBiomes
extends RefCounted
## What grows and lies on the ground at a point, 0 to 1 each: woods, dry grass, rock. The
## terrain colours and the scenery read these; the strip (Biomes) and the generated map
## (LandBiomes) answer them their own way (#472).


func forest(_x: float, _z: float) -> float:
	return 0.0


func dry(_x: float, _z: float) -> float:
	return 0.0


func rock(_x: float, _z: float) -> float:
	return 0.0
