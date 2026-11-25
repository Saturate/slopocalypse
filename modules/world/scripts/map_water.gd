class_name MapWater
extends WaterBodies
## A generated map's ponds and sea as water bodies (#472, #454). A pond's outline is the hull
## round its pond (good enough for drawing: the terrain hides the surface wherever the ground
## is above it), but water is only where the map's pond really is: a road cut or hollow
## inside the hull and below the level stays dry. The sea's outline is a square round the
## whole map; it is water only where WorldLand says the sea reaches.

var land: WorldLand
## The sea's index in `bodies`, or -1 on a map without one.
var sea := -1


func body_at(x: float, z: float) -> int:
	if land == null:
		return super.body_at(x, z)
	if sea >= 0 and land.is_sea(x, z):
		return sea
	if is_nan(land.water_level(x, z)):
		return -1
	var p := Vector2(x, z)
	for i in bodies.size():
		var b := bodies[i]
		if i != sea and (b["box"] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, b["outline"]):
			return i
	return -1


## As WaterBodies.flood for the ponds; a crater by the sea (its rim within the sea's bank)
## that dips below sea level fills to it, and one out in the sea is covered already.
func flood(centre: Vector3, radius: float, depth: float) -> Vector4:
	var puddle := super.flood(centre, radius, depth)
	if puddle != Vector4.ZERO or sea < 0 or land == null:
		return puddle
	var level := land.sea_level
	var bottom := centre.y - depth
	if bottom >= level or depth <= 0.0 or land.is_sea(centre.x, centre.z):
		return Vector4.ZERO
	var reach := radius + bank
	var by_sea := false
	for k in SEA_PROBES:
		var d := Vector2.from_angle(TAU * k / SEA_PROBES) * reach
		if land.is_sea(centre.x + d.x, centre.z + d.y):
			by_sea = true
			break
	if not by_sea:
		return Vector4.ZERO
	var at_surface := radius * sqrt(minf((level - bottom) / depth, 1.0))
	if at_surface <= 0.05:
		return Vector4.ZERO
	puddle = Vector4(centre.x, centre.z, at_surface, level)
	puddles.append(puddle)
	return puddle


## Points round a crater looked at for the sea.
const SEA_PROBES := 8
