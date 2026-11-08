extends GdUnitTestSuite
## The lighting follows the clock: a sun and sky recoloured for the hour, stars at night,
## and the server can set the time.

const MODULE := "res://modules/daytime/daytime_module.gd"


func _world_parts() -> Array:
	var sun: DirectionalLight3D = auto_free(DirectionalLight3D.new())
	var env := Environment.new()
	env.sky = Sky.new()
	env.sky.sky_material = ProceduralSkyMaterial.new()
	return [sun, env]


func test_night_dims_the_light_and_shows_stars() -> void:
	var parts := _world_parts()
	var lighting: DayLighting = auto_free(DayLighting.new())
	lighting.attach(parts[0], parts[1])
	var clock := DayClock.from_data()
	clock.set_hour(13.0)
	lighting.apply(clock)
	var sun: DirectionalLight3D = parts[0]
	var sky := (parts[1] as Environment).sky.sky_material as ProceduralSkyMaterial
	var day_energy := sun.light_energy
	assert_float(sky.sky_cover_modulate.a).is_equal(0.0)
	clock.set_hour(1.0)
	lighting.apply(clock)
	assert_float(sun.light_energy).is_less(day_energy)
	assert_float(sky.sky_cover_modulate.a).is_equal(1.0)
	assert_object(sky.sky_cover).is_not_null()


func test_the_light_moves_with_the_hour() -> void:
	var parts := _world_parts()
	var lighting: DayLighting = auto_free(DayLighting.new())
	lighting.attach(parts[0], parts[1])
	var clock := DayClock.from_data()
	var sun: DirectionalLight3D = parts[0]
	clock.set_hour(8.0)
	lighting.apply(clock)
	var morning := -sun.basis.z
	clock.set_hour(17.0)
	lighting.apply(clock)
	assert_float(morning.angle_to(-sun.basis.z)).is_greater(deg_to_rad(20.0))


func test_the_server_sets_the_time_and_the_clock_runs() -> void:
	var module: Node = auto_free((load(MODULE) as GDScript).new())
	add_child(module)
	var clock: DayClock = module.call(&"clock")
	module.call(&"server_set_hour", 21.0)
	assert_float(clock.hour).is_equal_approx(21.0, 0.001)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_float(clock.hour).is_greater(21.0)
