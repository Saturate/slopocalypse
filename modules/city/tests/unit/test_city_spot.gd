extends GdUnitTestSuite
## The city stands beside the road and stays off it even where the road bends its way.


class BendingGround:
	extends Node
	## Straight down -z, then from 200 m out bending towards +x by `bend` metres per metre.
	var bend := 0.0

	func road_point(metres: float) -> Vector3:
		return Vector3(maxf(metres - 200.0, 0.0) * bend * maxf(metres - 200.0, 0.0) / 100.0, 0.0, -metres)

	func ground_height(_x: float, _z: float) -> float:
		return 0.0


const CITY := "res://modules/city/city_module.gd"


func _spot(ground: Node) -> Transform3D:
	return (load(CITY) as GDScript).call(&"spot", ground, _cfg())


func _cfg() -> Dictionary:
	return {"at": 260.0, "side": 18.0, "size": 150.0}


## The nearest the road comes to the footprint's edge, over the stretch the city lines.
func _gap(ground: BendingGround, where: Transform3D, size: float) -> float:
	var nearest := INF
	# Finer than the city's own road samples, so a stretch slipping between those shows.
	for i in 2400:
		var local := where.affine_inverse() * ground.road_point(float(i) * 0.25)
		var outside := Vector2(maxf(absf(local.x) - size / 2.0, 0.0), maxf(absf(local.z) - size / 2.0, 0.0))
		nearest = minf(nearest, outside.length())
	return nearest


func test_on_a_straight_road_the_near_edge_is_side_away() -> void:
	var ground: BendingGround = auto_free(BendingGround.new())
	var where := _spot(ground)
	assert_float(_gap(ground, where, 150.0)).is_equal_approx(18.0, 0.5)


func test_a_road_bending_towards_it_never_enters_the_city() -> void:
	var ground: BendingGround = auto_free(BendingGround.new())
	ground.bend = 0.2
	var where := _spot(ground)
	# Off the road by `side`, and no further: pushed out just enough.
	assert_float(_gap(ground, where, 150.0)).is_between(18.0 - 0.5, 18.0 + 0.5)
