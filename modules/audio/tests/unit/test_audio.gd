extends GdUnitTestSuite
## Every sound exists and is audible; events turn into sounds in the right place.

const MODULE := "res://modules/audio/audio_module.gd"


func test_every_sound_is_synthesised() -> void:
	for sound in ["rifle", "pistol", "suppressed", "impact", "hit", "explosion", "footstep", "reload", "pickup", "hurt", "wind"]:
		var wav := SoundBank.get_sound(sound)
		assert_object(wav).override_failure_message(sound).is_not_null()
		assert_float(wav.get_length()).override_failure_message(sound).is_greater(0.02)
		# Not silence: some sample is loud.
		var loud := 0
		for i in range(0, wav.data.size(), 2 * 64):
			loud = maxi(loud, absi(wav.data.decode_s16(i)))
		assert_int(loud).override_failure_message(sound).is_greater(2000)
	assert_int(SoundBank.get_sound("wind").loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)


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
