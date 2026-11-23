extends GdUnitTestSuite
## A road that doubles back on itself stays where its points are (#512): rounding the
## reversal must not throw the arc's start hundreds of millions of metres off, on any
## platform's rounding of the turn.

const RADIUS := 12.0
## A reversal's turn as single-precision atan2 gives it: glibc rounds up past pi, Apple's
## libm rounds down.
const PI_ROUNDED_UP := 3.1415927410125732
const PI_ROUNDED_DOWN := 3.1415925025939941


func test_the_half_turn_tangent_stays_positive_and_large_at_a_reversal() -> void:
	for turn: float in [PI_ROUNDED_UP, -PI_ROUNDED_UP, PI_ROUNDED_DOWN, -PI_ROUNDED_DOWN]:
		assert_float(RoadNetwork.half_turn_tangent(turn)).is_greater(1e5)


func test_an_ordinary_corner_keeps_its_tangent() -> void:
	assert_float(RoadNetwork.half_turn_tangent(PI / 2.0)).is_equal_approx(1.0, 1e-9)
	assert_float(RoadNetwork.half_turn_tangent(-PI / 3.0)).is_equal_approx(tan(PI / 6.0), 1e-9)


func test_a_road_that_doubles_back_stays_near_its_points() -> void:
	var points := PackedVector2Array([Vector2(-484.0, -392.0), Vector2(-436.0, -392.0), Vector2(-475.0, -392.0)])
	var curve := RoadNetwork._round_corners(points, RADIUS)
	for p in curve:
		assert_float(p.x).is_between(-484.0 - RADIUS, -436.0 + RADIUS)
		assert_float(p.y).is_between(-392.0 - RADIUS, -392.0 + RADIUS)
	# Resampled every 2 m it stays a short line, not millions of points.
	assert_int(RoadNetwork._resample(curve, 2.0).size()).is_less(100)
