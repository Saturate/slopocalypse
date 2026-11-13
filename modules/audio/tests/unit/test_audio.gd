extends GdUnitTestSuite
## Every sound exists and is audible; events turn into sounds in the right place.

const MODULE := "res://modules/audio/audio_module.gd"


func test_every_sound_is_synthesised() -> void:
	for sound in ["rifle", "pistol", "suppressed", "impact", "hit", "explosion", "footstep", "reload", "pickup", "hurt", "wind", "crickets", "bird0", "bird1", "bird2", "bird3"]:
		var wav := SoundBank.get_sound(sound)
		assert_object(wav).override_failure_message(sound).is_not_null()
		assert_float(wav.get_length()).override_failure_message(sound).is_greater(0.02)
		# Not silence: some sample is loud.
		var loud := 0
		for i in range(0, wav.data.size(), 2 * 64):
			loud = maxi(loud, absi(wav.data.decode_s16(i)))
		assert_int(loud).override_failure_message(sound).is_greater(2000)
	for family in SoundBank.SURFACE_FAMILIES:
		for sound in ["hit_" + family, "break_" + family]:
			var wav := SoundBank.get_sound(sound)
			assert_object(wav).override_failure_message(sound).is_not_null()
			var loud := 0
			for i in range(0, wav.data.size(), 2 * 16):
				loud = maxi(loud, absi(wav.data.decode_s16(i)))
			assert_int(loud).override_failure_message(sound).is_greater(2000)
	assert_object(SoundBank.get_sound("collapse")).is_not_null()
	assert_int(SoundBank.get_sound("wind").loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)
	assert_int(SoundBank.get_sound("crickets").loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)


func test_wind_is_long() -> void:
	var wind := SoundBank.get_sound("wind")
	# Long enough that the loop is not heard repeating.
	assert_float(wind.get_length()).is_greater(15.0)


func test_bird_songs_differ() -> void:
	var lengths := {}
	for v in SoundBank.BIRD_VARIANTS:
		lengths[snappedf(SoundBank.get_sound("bird%d" % v).get_length(), 0.01)] = true
	assert_int(lengths.size()).is_equal(SoundBank.BIRD_VARIANTS)


func test_birds_sing_by_day_and_crickets_take_over_at_night() -> void:
	var module: Node = (load(MODULE) as GDScript).new()
	module.set(&"enabled", true)
	add_child(auto_free(module))
	var camera: Camera3D = auto_free(Camera3D.new())
	add_child(camera)
	camera.make_current()
	var crickets := module.get_node("Crickets") as AudioStreamPlayer
	EventBus.publish(&"daytime.hour", {"daylight": 1.0})
	module.set(&"_next_bird", 0.0)
	module.call(&"_ambience", 0.016)
	assert_float(crickets.volume_db).is_less_equal(module.get(&"SILENT_DB") + 0.01)
	var day_voices := _voices(module)
	assert_int(day_voices).is_greater(0)
	EventBus.publish(&"daytime.hour", {"daylight": 0.0})
	for n in 20:
		module.set(&"_next_bird", 0.0)
		module.call(&"_ambience", 0.016)
	assert_int(_voices(module)).is_equal(day_voices)
	assert_float(crickets.volume_db).is_greater(-40.0)


func _voices(module: Node) -> int:
	return module.get_children().filter(func(n: Node) -> bool: return n is AudioStreamPlayer3D).size()


func test_a_suppressor_quiets_and_a_semi_auto_is_a_pistol() -> void:
	var gun: Node = auto_free(Node.new())
	assert_str((load(MODULE) as GDScript).call(&"shot_sound", gun)).is_equal("rifle")
	gun.set_meta(&"build", {"muzzle": "muz_supp"})
	assert_str((load(MODULE) as GDScript).call(&"shot_sound", gun)).is_equal("suppressed")


func test_a_shot_plays_where_it_was_fired() -> void:
	var module: Node = (load(MODULE) as GDScript).new()
	module.set(&"enabled", true)
	add_child(auto_free(module))
	EventBus.publish(&"weapon.fired", {"from": Vector3(5, 1, 2), "to": Vector3(5, 1, -50), "damage": 0.0})
	var players := module.get_children().filter(func(n: Node) -> bool: return n is AudioStreamPlayer3D)
	assert_int(players.size()).is_greater(0)
	assert_vector((players[0] as Node3D).global_position).is_equal(Vector3(5, 1, 2))


func _surface_module() -> Node:
	var module: Node = (load(MODULE) as GDScript).new()
	module.set(&"enabled", true)
	add_child(auto_free(module))
	return module


func _players_of(module: Node) -> Array:
	return module.get_children().filter(func(n: Node) -> bool: return n is AudioStreamPlayer3D)


func test_every_breakable_material_has_a_sound_family() -> void:
	var module := _surface_module()
	# Read by path: the audio module needs no other module, and without the voxel kit there
	# is nothing to check.
	const MATERIALS := "res://modules/voxkit/data/materials.json"
	if not FileAccess.file_exists(MATERIALS):
		return
	for m: Dictionary in (JSON.parse_string(FileAccess.get_file_as_string(MATERIALS)) as Dictionary)["materials"]:
		var family := str(module.call(&"surface_family", str(m["name"])))
		if str(m["name"]) == "default":
			continue
		assert_bool(family in SoundBank.SURFACE_FAMILIES).override_failure_message("no sound family for %s" % m["name"]).is_true()


func test_a_surface_hit_plays_its_materials_sound_where_it_hit() -> void:
	var module := _surface_module()
	EventBus.publish(&"missions.surface_hit", {"position": Vector3(3, 1, -9), "material": "sheet_metal", "count": 1})
	var voices := _players_of(module)
	assert_int(voices.size()).is_equal(1)
	assert_object((voices[0] as AudioStreamPlayer3D).stream).is_same(SoundBank.get_sound("hit_metal"))
	assert_vector((voices[0] as Node3D).global_position).is_equal(Vector3(3, 1, -9))


func test_breaking_glass_and_a_landing_each_make_their_sound() -> void:
	var module := _surface_module()
	EventBus.publish(&"missions.surface_broke", {"position": Vector3.ZERO, "material": "tempered_glass", "count": 4})
	EventBus.publish(&"missions.surface_landed", {"position": Vector3.ZERO, "material": "", "count": 2})
	var streams := _players_of(module).map(func(v: AudioStreamPlayer3D) -> AudioStream: return v.stream)
	assert_bool(streams.has(SoundBank.get_sound("break_glass_small"))).is_true()
	assert_bool(streams.has(SoundBank.get_sound("collapse"))).is_true()


func test_a_shot_into_something_with_its_own_surface_sounds_makes_no_plain_impact() -> void:
	var module := _surface_module()
	var wall: Node = auto_free(Node.new())
	wall.set_meta(&"surface_sounds", true)
	EventBus.publish(&"weapon.fired", {"from": Vector3(0, 1, 0), "to": Vector3(0, 1, -10), "damage": 0.0, "collider": wall})
	var streams := _players_of(module).map(func(v: AudioStreamPlayer3D) -> AudioStream: return v.stream)
	assert_bool(streams.has(SoundBank.get_sound("impact"))).is_false()
