extends GdUnitTestSuite
## Drawing glowsticks on a client (#447): your own stick lights the world gently and leaves
## your first-person arms and gun out, giving them only a faint tint of their own; everyone
## else's is drawn with the usual light; a dropped stick is a stick lying on the ground.

const PLAYER := "res://modules/player/scenes/player.tscn"

var _view: GlowstickView


func before_test() -> void:
	Armband.use_config(Data.load_json(Armband.CONFIG))
	_view = auto_free(GlowstickView.new())
	_view.config = Data.load_json(GlowstickRules.CONFIG)
	_view.set_process(false)
	add_child(_view)


func _spawn(peer: int) -> PlayerController:
	var player: PlayerController = auto_free((load(PLAYER) as PackedScene).instantiate())
	player.set_physics_process(false)
	player.set_meta(&"peer_id", peer)
	player.add_to_group(&"players")
	add_child(player)
	return player


func _stick_on(player: Node) -> Node3D:
	return player.find_child(GlowstickView.STICK, true, false) as Node3D


func test_your_own_light_leaves_your_arms_and_gun_out_and_tints_them_faintly() -> void:
	var me := multiplayer.get_unique_id()
	var player := _spawn(me)
	_view.carriers = {me: [true, 100.0]}
	_view.refresh()
	var stick := _stick_on(player)
	assert_object(stick).is_not_null()
	var own: Dictionary = _view.config["own_light"]
	var light := stick.get_node("Light") as OmniLight3D
	assert_int(light.light_cull_mask & RenderLayers.FIRST_PERSON).is_equal(0)
	# It still lights the world and the people round you.
	assert_int(light.light_cull_mask & RenderLayers.DEFAULT).is_equal(RenderLayers.DEFAULT)
	assert_int(light.light_cull_mask & RenderLayers.NO_DECALS).is_equal(RenderLayers.NO_DECALS)
	assert_float(light.light_energy).is_equal_approx(float(own["energy"]), 0.001)
	assert_float(light.omni_range).is_equal_approx(float(own["range"]), 0.001)
	var tint := stick.get_node("ViewLight") as OmniLight3D
	assert_int(tint.light_cull_mask).is_equal(RenderLayers.FIRST_PERSON)
	assert_float(tint.light_energy).is_equal_approx(float(own["view_energy"]), 0.001)
	assert_float(tint.light_energy).is_less(float(own["energy"]) * 2.0)


func test_someone_elses_stick_has_the_usual_light() -> void:
	var other := multiplayer.get_unique_id() + 41
	var player := _spawn(other)
	_view.carriers = {other: [true, 100.0]}
	_view.refresh()
	var stick := _stick_on(player)
	var usual: Dictionary = _view.config["light"]
	var light := stick.get_node("Light") as OmniLight3D
	assert_int(light.light_cull_mask & RenderLayers.FIRST_PERSON).is_equal(RenderLayers.FIRST_PERSON)
	assert_float(light.light_energy).is_equal_approx(float(usual["energy"]), 0.001)
	assert_float(light.omni_range).is_equal_approx(float(usual["range"]), 0.001)
	assert_object(stick.get_node_or_null("ViewLight")).is_null()


func test_a_dropped_stick_is_a_stick_lying_on_the_ground() -> void:
	var at := Vector3(3.0, 0.0, -2.0)
	_view.ground = [[9, at, "players"]]
	_view.refresh()
	var dropped := _view.find_child("Ground%s" % GlowstickView.STICK, true, false) as Node3D
	assert_object(dropped).is_not_null()
	var mesh := dropped.get_node("Stick") as MeshInstance3D
	assert_bool(mesh.visible).is_true()
	assert_int(mesh.cast_shadow).is_not_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
	# Lying flat: its length runs along the ground, just above it.
	var along := mesh.global_basis.y.normalized()
	assert_float(absf(along.y)).is_less(0.05)
	assert_float(mesh.global_position.y - at.y).is_between(0.0, 0.1)
	# Glowing less than on a chest, so its shape reads instead of blooming into a blob.
	var material := (mesh.mesh as BoxMesh).material as StandardMaterial3D
	assert_float(material.emission_energy_multiplier).is_equal_approx(float(_view.config["ground"]["glow"]), 0.001)
	assert_float(material.emission_energy_multiplier).is_less(float(_view.config["stick"]["glow"]))
