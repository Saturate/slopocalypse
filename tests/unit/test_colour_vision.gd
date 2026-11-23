extends GdUnitTestSuite
## ColourVision: greys look the same to everyone, red and green fall together with red-green
## colour blindness, and blue and yellow stay apart with it.


func test_greys_are_seen_the_same_by_everyone() -> void:
	for kind: StringName in ColourVision.KINDS:
		for grey: Color in [Color.BLACK, Color(0.5, 0.5, 0.5), Color.WHITE]:
			assert_float(ColourVision.difference(grey, ColourVision.simulate(grey, kind))).is_less(0.01)


func test_red_and_green_fall_together_without_green_cones() -> void:
	var green := Color(0.1, 0.75, 0.12)
	var orange := Color(1.0, 0.42, 0.0)
	assert_float(ColourVision.difference(green, orange)).is_greater(0.2)
	assert_float(ColourVision.difference(green, orange, ColourVision.DEUTAN)).is_less(0.05)


func test_blue_and_yellow_stay_apart_with_red_green_colour_blindness() -> void:
	for kind: StringName in [ColourVision.PROTAN, ColourVision.DEUTAN]:
		assert_float(ColourVision.difference(Color(0.05, 0.28, 1.0), Color(1.0, 0.77, 0.0), kind)).is_greater(0.3)


func test_an_image_is_simulated_pixel_by_pixel() -> void:
	var image := Image.create(2, 1, false, Image.FORMAT_RGBA8)
	image.set_pixel(0, 0, Color(1.0, 0.0, 0.0))
	image.set_pixel(1, 0, Color.WHITE)
	var seen := ColourVision.simulate_image(image, ColourVision.DEUTAN)
	assert_float(ColourVision.difference(seen.get_pixel(0, 0), ColourVision.simulate(Color(1.0, 0.0, 0.0), ColourVision.DEUTAN))).is_less(0.01)
	assert_float(ColourVision.difference(seen.get_pixel(1, 0), Color.WHITE)).is_less(0.01)
	assert_that(image.get_pixel(0, 0)).is_equal(Color(1.0, 0.0, 0.0))
