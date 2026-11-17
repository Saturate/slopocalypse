extends GdUnitTestSuite
## However many lights there are, only the nearest few are real: a handful with shadows, some
## more without, and the rest off; they fade across those lines instead of popping.


func test_ranks_go_by_distance() -> void:
	var r := LightBudget.ranks([50.0, 5.0, 20.0, 80.0, 1.0], 1, 2)
	assert_array(r).is_equal([LightBudget.OFF, LightBudget.LIT, LightBudget.LIT, LightBudget.OFF, LightBudget.SHADOW])


func _lights(count: int, shadow: bool) -> Array[OmniLight3D]:
	var out: Array[OmniLight3D] = []
	for i in count:
		var light: OmniLight3D = auto_free(OmniLight3D.new())
		light.light_energy = 2.0
		light.shadow_enabled = shadow
		light.add_to_group(LightBudget.GROUP)
		add_child(light)
		light.global_position = Vector3(0, 0, -float(i) * 10.0)
		out.append(light)
	return out


func _budget() -> LightBudget:
	var budget: LightBudget = auto_free(LightBudget.new())
	budget.max_shadow = 4
	budget.max_lit = 16
	budget.fade = 0.3
	budget.eye_override = Vector3.ZERO
	budget.set_process(false)
	add_child(budget)
	return budget


func test_thirty_lamps_in_view_light_at_most_the_budget() -> void:
	var lights := _lights(30, true)
	var budget := _budget()
	budget.step(1.0)
	var on := lights.filter(func(l: OmniLight3D) -> bool: return l.visible)
	var shadows := lights.filter(func(l: OmniLight3D) -> bool: return l.shadow_enabled)
	assert_int(on.size()).is_equal(20)
	assert_int(shadows.size()).is_equal(4)
	assert_bool(lights[0].shadow_enabled).is_true()
	assert_bool(lights[4].shadow_enabled).is_false()
	assert_bool(lights[29].visible).is_false()
	assert_float(lights[0].light_energy).is_equal_approx(2.0, 0.0001)


func test_lights_fade_instead_of_popping() -> void:
	var lights := _lights(3, false)
	var budget := _budget()
	budget.max_shadow = 0
	budget.max_lit = 1
	budget.step(0.15)
	# Half way in after half the fade.
	assert_float(lights[0].light_energy).is_equal_approx(1.0, 0.0001)
	budget.step(1.0)
	# The eye moves to the far one: the near one fades out over the same time.
	budget.eye_override = Vector3(0, 0, -20)
	budget.step(0.15)
	assert_float(lights[0].light_energy).is_equal_approx(1.0, 0.0001)
	assert_float(lights[2].light_energy).is_equal_approx(1.0, 0.0001)
	budget.step(1.0)
	assert_bool(lights[0].visible).is_false()
	# A light that goes (a bulb shot out) is simply forgotten.
	lights[1].free()
	budget.step(0.1)
	# A light made without shadows never gets them.
	assert_bool(lights[2].shadow_enabled).is_false()
