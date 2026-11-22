extends GdUnitTestSuite
## The map viewer's API on a server's admin pages (#448): lists the recipes, hands one out,
## renders a recipe and seed on a worker thread and serves the image, and refuses bad input.

var _api: MapApi


func before_test() -> void:
	_api = auto_free(MapApi.new())
	add_child(_api)


func _ask(method: String, path: String, body: String = "") -> Variant:
	return _api.handle({"method": method, "path": path, "query": "", "headers": {}, "body": body})


func _json(reply: Variant) -> Dictionary:
	var parsed: Variant = JSON.parse_string(str((reply as Array)[2]))
	return parsed if parsed is Dictionary else {}


## The server's own limit on a waiting answer; a frame count was too short on a busy CI
## runner, where a build sometimes takes over 4 s.
const WAIT_MS := 60_000


## Polls a waiting answer the way the web module does, a frame at a time.
func _wait(reply: Variant) -> Array:
	if reply is Array:
		return reply
	var poll: Callable = (reply as Dictionary)["wait"]
	var deadline := Time.get_ticks_msec() + WAIT_MS
	while Time.get_ticks_msec() < deadline:
		var answer: Variant = poll.call()
		if answer is Array:
			return answer
		await get_tree().process_frame
	return [0, "", "timed out"]


func test_it_lists_the_recipes_and_hands_one_out() -> void:
	var maps: Array = _json(_ask("GET", "/admin/api/v1/maps"))["maps"]
	assert_bool(maps.has("grassland")).is_true()
	var recipe: Variant = JSON.parse_string(str((_ask("GET", "/admin/api/v1/maps/grassland") as Array)[2]))
	assert_bool(recipe is Dictionary and (recipe as Dictionary).has("relief")).is_true()
	assert_int(int((_ask("GET", "/admin/api/v1/maps/../secrets") as Array)[0])).is_equal(404)


func test_a_render_comes_back_with_its_image_and_stats_and_is_kept() -> void:
	var body := JSON.stringify({"map": "grassland", "seed": 3, "pixels": 64, "layers": ["roads"]})
	var reply := await _wait(_ask("POST", "/admin/api/v1/maps/render", body))
	assert_int(int(reply[0])).is_equal(200)
	var out := _json(reply)
	assert_bool((out["stats"] as Dictionary).has("summary")).is_true()
	var image: Array = _ask("GET", str(out["image"]))
	assert_int(int(image[0])).is_equal(200)
	assert_str(str(image[1])).is_equal("image/png")
	assert_int((image[2] as PackedByteArray).size()).is_greater(100)
	# Asked again: answered at once from what was kept.
	assert_bool(_ask("POST", "/admin/api/v1/maps/render", body) is Array).is_true()


func test_bad_input_is_refused_before_any_work() -> void:
	for body: String in ["not json", '{"map": "nowhere"}', '{"map": "grassland", "seed": -1}', '{"map": "grassland", "pixels": 99999}', '{"map": "grassland", "layers": ["bombs"]}', '{"map": "grassland", "pixels": [1]}']:
		var reply: Variant = _ask("POST", "/admin/api/v1/maps/render", body)
		assert_bool(reply is Array).override_failure_message(body).is_true()
		assert_int(int((reply as Array)[0])).override_failure_message(body).is_equal(400)


func test_a_broken_edited_recipe_is_an_answer_not_a_script_error() -> void:
	var body := JSON.stringify({"map": "grassland", "seed": 1, "pixels": 64, "recipe": {"size": 512}})
	var reply: Variant = _ask("POST", "/admin/api/v1/maps/render", body)
	assert_bool(reply is Array).is_true()
	assert_int(int((reply as Array)[0])).is_equal(400)
	assert_str(str((reply as Array)[2])).contains("relief")


func test_both_shipped_recipes_pass_the_check() -> void:
	for name in MapApi.names():
		var recipe: Variant = JSON.parse_string(FileAccess.get_file_as_string(MapApi.MAPS_DIR.path_join(name + ".json")))
		assert_str(MapRender.check(recipe)).override_failure_message(name).is_empty()


func test_values_that_would_keep_a_render_busy_for_good_are_refused() -> void:
	var stored: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MapApi.MAPS_DIR.path_join("grassland.json")))
	var cases := {"roads.sample": func(r: Dictionary) -> void: r["roads"]["sample"] = 0,
		"size": func(r: Dictionary) -> void: r["size"] = 100000,
		"zones.cell": func(r: Dictionary) -> void: r["zones"]["cell"] = 0.01,
		"layers": func(r: Dictionary) -> void: r["layers"] = (r["layers"] as Array).duplicate() + (r["layers"] as Array) + (r["layers"] as Array),
		"octaves": func(r: Dictionary) -> void: r["layers"][0]["octaves"] = 50,
		"min_radius": func(r: Dictionary) -> void: r["roads"]["kinds"]["highway"]["min_radius"] = 1e9}
	for name: String in cases:
		var recipe := stored.duplicate(true)
		(cases[name] as Callable).call(recipe)
		assert_str(MapRender.check(recipe)).override_failure_message(name).contains(name)


func test_a_close_up_of_a_region_reuses_the_built_map() -> void:
	var whole := JSON.stringify({"map": "grassland", "seed": 4, "pixels": 64, "layers": ["roads"]})
	assert_int(int((await _wait(_ask("POST", "/admin/api/v1/maps/render", whole)))[0])).is_equal(200)
	var close := JSON.stringify({"map": "grassland", "seed": 4, "pixels": 64, "layers": ["roads"], "region": {"left": -100, "top": -100, "size": 200}})
	var started := Time.get_ticks_msec()
	var reply := await _wait(_ask("POST", "/admin/api/v1/maps/render", close))
	var took := Time.get_ticks_msec() - started
	assert_int(int(reply[0])).is_equal(200)
	assert_float(float((_json(reply)["region"] as Dictionary)["size"])).is_equal(200.0)
	# Drawing 64 pixels of a kept map takes a fraction of building it again.
	assert_int(took).is_less(int(_json(reply)["stats"]["summary"]["built in"].to_int()))


func test_a_region_outside_the_map_or_too_small_is_refused() -> void:
	for region: Dictionary in [{"left": 5000, "top": 0, "size": 200}, {"left": 0, "top": 0, "size": 4}, {"left": 0, "top": 0}]:
		var body := JSON.stringify({"map": "grassland", "seed": 1, "pixels": 64, "region": region})
		var reply: Variant = _ask("POST", "/admin/api/v1/maps/render", body)
		assert_bool(reply is Array).override_failure_message(str(region)).is_true()
		assert_int(int((reply as Array)[0])).override_failure_message(str(region)).is_equal(400)
