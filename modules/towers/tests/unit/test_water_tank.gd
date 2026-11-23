extends GdUnitTestSuite
## A shot tank drains through every hole below its water, faster the more water is over a
## hole, until the level reaches the lowest pouring hole. Every machine works it out from the
## holes and when they were made, so the level is never sent.


func _tank() -> WaterTank:
	var t := WaterTank.new()
	t.area = 4.0
	t.height = 3.0
	t.level = 2.7
	t.flow = 0.05
	t.max_holes = 3
	return t


func test_a_hole_below_the_water_pours_and_one_above_does_not() -> void:
	var t := _tank()
	t.add_hole(2.9, 0.0)
	t.advance(10.0)
	assert_float(t.level).is_equal(2.7)
	t.add_hole(1.0, 10.0)
	assert_int(t.pouring().size()).is_equal(1)
	t.advance(10.0)
	assert_float(t.level).is_less(2.7)
	assert_float(t.poured).is_greater(0.0)


func test_it_drains_faster_with_more_water_over_the_hole() -> void:
	var t := _tank()
	t.add_hole(0.0, 0.0)
	t.advance(1.0)
	var early := 2.7 - t.level
	var mid := t.level
	t.level = 0.4
	t.advance(1.0)
	var late := 0.4 - t.level
	assert_float(early).is_greater(late)
	assert_float(mid).is_less(2.7)


func test_it_stops_at_the_lowest_hole() -> void:
	var t := _tank()
	t.add_hole(1.5, 0.0)
	t.advance(5000.0)
	assert_float(t.level).is_equal_approx(1.5, 0.01)
	assert_int(t.pouring().size()).is_equal(0)
	# Water out is what the level lost, over the tank's area.
	assert_float(t.poured).is_equal_approx((2.7 - t.level) * 4.0, 0.001)


func test_only_max_holes_pour() -> void:
	var t := _tank()
	for i in 6:
		t.add_hole(0.5 + i * 0.1, 0.0)
	assert_int(t.pouring().size()).is_equal(3)


func test_a_late_joiner_given_only_holes_and_ages_lands_on_the_same_level() -> void:
	var live := _tank()
	live.add_hole(1.0, 0.0)
	for i in 600:
		live.advance(1.0 / 60.0)
		if i == 300:
			live.add_hole(2.0, 5.0)
	# Holes 10 s and 5 s old.
	var late := _tank()
	late.catch_up([{"height": 1.0, "age": 10.0}, {"height": 2.0, "age": 5.0}])
	assert_float(late.level).is_equal_approx(live.level, 0.01)


func test_the_puddle_grows_with_what_poured_up_to_its_limit() -> void:
	assert_float(WaterTank.puddle_radius(0.0, 0.05, 6.0)).is_equal(0.0)
	var small := WaterTank.puddle_radius(0.5, 0.05, 6.0)
	assert_float(small).is_equal_approx(sqrt(0.5 / (PI * 0.05)), 0.0001)
	assert_float(WaterTank.puddle_radius(500.0, 0.05, 6.0)).is_equal(6.0)
