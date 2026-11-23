extends GdUnitTestSuite
## Recorded sounds beside the generated ones: a recording wins, several takes share the
## plays, a sound without one falls back to the generated sound, and every play varies its
## pitch and volume within the ranges in the data. The .ogg files are silence written at
## test time, so no audio is committed for the tests.

const MODULE := "res://modules/audio/audio_module.gd"
const TinyOgg := preload("res://modules/audio/tests/unit/tiny_ogg.gd")

var _dirs: Array[String] = []


func after_test() -> void:
	SoundBank.use_recordings(SoundBank.default_dirs())
	for dir in _dirs:
		for file in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(file))
		DirAccess.remove_absolute(dir)
	_dirs.clear()


## A fresh folder under user:// holding silent takes of `seconds` each, by file name.
func _folder(files: Dictionary) -> String:
	var dir := "user://test_audio_recordings_%d_%d" % [Time.get_ticks_usec(), _dirs.size()]
	DirAccess.make_dir_recursive_absolute(dir)
	_dirs.append(dir)
	for file: String in files:
		TinyOgg.write(dir.path_join(file), float(files[file]))
	return dir


func _module() -> Node:
	var module: Node = (load(MODULE) as GDScript).new()
	module.set(&"enabled", true)
	add_child(auto_free(module))
	return module


func test_a_recorded_file_wins_over_the_generated_sound() -> void:
	SoundBank.use_recordings(PackedStringArray([_folder({"rifle.ogg": 0.2})]))
	var stream := SoundBank.get_sound("rifle")
	assert_object(stream).is_instanceof(AudioStreamOggVorbis)
	assert_float(stream.get_length()).is_greater(0.1)
	# A sound with no recording is still made in code.
	assert_object(SoundBank.get_sound("pistol")).is_same(SoundBank.generated("pistol"))
	# And the module plays the recording.
	var voice := _module().call(&"play_at", "rifle", Vector3.ZERO, 50.0) as AudioStreamPlayer3D
	assert_object(voice.stream).is_same(stream)


func test_several_takes_are_all_played() -> void:
	SoundBank.use_recordings(PackedStringArray([_folder({"explosion_1.ogg": 0.1, "explosion_2.ogg": 0.2, "explosion_3.ogg": 0.3})]))
	var takes := SoundBank.takes("explosion")
	assert_int(takes.size()).is_equal(3)
	var heard := {}
	for i in 300:
		var stream := SoundBank.get_sound("explosion")
		assert_bool(takes.has(stream)).is_true()
		heard[stream] = true
	assert_int(heard.size()).is_equal(3)


func test_a_missing_recording_falls_back_to_the_generated_sound() -> void:
	SoundBank.use_recordings(PackedStringArray([_folder({"pistol.ogg": 0.1}), "user://test_audio_no_such_folder"]))
	assert_object(SoundBank.get_sound("rifle")).is_same(SoundBank.generated("rifle"))
	assert_array(SoundBank.takes("rifle")).is_empty()
	# The built-in folder through the resource loader, as an export reads it: no audio in
	# it yet, so everything is generated.
	SoundBank.use_recordings(PackedStringArray([SoundBank.SOUNDS_DIR]))
	assert_object(SoundBank.get_sound("explosion")).is_same(SoundBank.generated("explosion"))


func test_a_later_folder_replaces_a_sounds_takes() -> void:
	var built_in := _folder({"wind_1.ogg": 0.1, "wind_2.ogg": 0.2, "bird0.ogg": 0.1})
	var tweaks := _folder({"wind.ogg": 0.3})
	SoundBank.use_recordings(PackedStringArray([built_in, tweaks]))
	var wind := SoundBank.takes("wind")
	assert_int(wind.size()).is_equal(1)
	assert_float(wind[0].get_length()).is_greater(0.25)
	# A loop stays a loop when it is recorded; a one-off doesn't loop.
	assert_bool((wind[0] as AudioStreamOggVorbis).loop).is_true()
	assert_int(SoundBank.takes("bird0").size()).is_equal(1)
	assert_bool((SoundBank.takes("bird0")[0] as AudioStreamOggVorbis).loop).is_false()


func test_file_names_map_to_sound_ids() -> void:
	assert_str(SoundBank.take_id("rifle.ogg")).is_equal("rifle")
	assert_str(SoundBank.take_id("rifle_12.ogg")).is_equal("rifle")
	assert_str(SoundBank.take_id("break_glass_small_2.ogg")).is_equal("break_glass_small")
	assert_str(SoundBank.take_id("hit_glass_small.ogg")).is_equal("hit_glass_small")
	assert_str(SoundBank.take_id("bird3.ogg")).is_equal("bird3")
	assert_str(SoundBank.take_id("README.md")).is_equal("")


func test_jitter_stays_within_its_range() -> void:
	var module := _module()
	var table: Dictionary = (module.get(&"config") as Dictionary)["jitter"]
	for sound: String in ["footstep", "rifle", "hit_metal", "bird2", "bolt_cycle"]:
		var spec: Dictionary = module.call(&"setting_for", table, sound, table["default"])
		var pitch: Array = spec.get("pitch", table["default"]["pitch"])
		var db: Array = spec.get("volume_db", table["default"]["volume_db"])
		var lowest := Vector2(INF, INF)
		var highest := Vector2(-INF, -INF)
		for i in 400:
			var shake: Vector2 = module.call(&"jitter", sound)
			lowest = lowest.min(shake)
			highest = highest.max(shake)
		assert_float(lowest.x).override_failure_message(sound).is_greater_equal(float(pitch[0]))
		assert_float(highest.x).override_failure_message(sound).is_less_equal(float(pitch[1]))
		assert_float(lowest.y).override_failure_message(sound).is_greater_equal(float(db[0]))
		assert_float(highest.y).override_failure_message(sound).is_less_equal(float(db[1]))
		# It really varies wherever the range is wider than nothing.
		if float(pitch[1]) > float(pitch[0]):
			assert_float(highest.x - lowest.x).override_failure_message(sound).is_greater((float(pitch[1]) - float(pitch[0])) * 0.5)


func test_each_play_varies_around_the_sounds_own_volume() -> void:
	var module := _module()
	var config: Dictionary = module.get(&"config")
	var base_db := float(config["volume_db"]["footstep"])
	var spec: Dictionary = config["jitter"]["footstep"]
	var pitches := {}
	for i in 30:
		var voice := module.call(&"play_at", "footstep", Vector3.ZERO, 20.0, 2.0) as AudioStreamPlayer3D
		# The caller's pitch rides on top of the jitter.
		assert_float(voice.pitch_scale).is_between(2.0 * float(spec["pitch"][0]), 2.0 * float(spec["pitch"][1]))
		assert_float(voice.volume_db).is_between(base_db + float(spec["volume_db"][0]), base_db + float(spec["volume_db"][1]))
		pitches[voice.pitch_scale] = true
	assert_int(pitches.size()).is_greater(1)


func test_bad_jitter_data_is_reported_and_plays_unvaried() -> void:
	var module := _module()
	module.set(&"config", {"jitter": {"default": "x", "rifle": "loud"}})
	Log.begin_capture()
	module.call(&"_check_jitter")
	var entries := Log.end_capture()
	assert_str(LogCapture.text(entries)).contains("default").contains("rifle")
	assert_vector(module.call(&"jitter", "rifle")).is_equal(Vector2(1.0, 0.0))
