class_name SmokeView
extends Node
## Client-only: draws the plumes the server announces. Big ones (`r1` over `fog_radius`)
## are fog volumes, lit by the world's volumetric fog, while the camera is close enough for
## that fog to reach them; small ones, and big ones past the fog's length, are a cloud of
## dithered quads (each pixel drawn or not, no blending), so they need no sorting and stay
## crisp under the pixel filter.

var config: Dictionary = {}
## id -> {volume, fog, cloud, material}
var _shown: Dictionary[int, Dictionary] = {}
var _quad: QuadMesh
## While the local player looks through a thermal sight, smoke barely shows.
var _thinned := 1.0


func _ready() -> void:
	EventBus.subscribe(&"smoke.spawned", _on_spawned)
	EventBus.subscribe(&"smoke.ended", _on_ended)
	EventBus.subscribe(&"weapons.thermal", _on_thermal)
	_quad = QuadMesh.new()
	_quad.size = Vector2.ONE * 0.9


func _exit_tree() -> void:
	EventBus.unsubscribe(&"smoke.spawned", _on_spawned)
	EventBus.unsubscribe(&"smoke.ended", _on_ended)
	EventBus.unsubscribe(&"weapons.thermal", _on_thermal)


func shown_count() -> int:
	return _shown.size()


func cloud_alpha(id: int) -> float:
	return (_shown[id]["material"] as StandardMaterial3D).albedo_color.a


func _on_spawned(p: Dictionary) -> void:
	var v := SmokeVolume.from_payload(p)
	var root := get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	var entry := {"volume": v}
	var material := _material(v)
	entry["material"] = material
	var cloud := _cloud(v, material)
	root.add_child(cloud)
	entry["cloud"] = cloud
	if v.r1 > float(config["fog_radius"]):
		var fog := FogVolume.new()
		fog.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
		var fm := FogMaterial.new()
		# Fog albedo is how much light it scatters back: a light grey takes the sun and the
		# sky's colour; the dark smoke colour would only absorb and read as a black ball.
		fm.albedo = _fog_albedo()
		fm.edge_fade = 0.3
		fm.density_texture = _billows(v.seed)
		fog.material = fm
		root.add_child(fog)
		entry["fog"] = fog
	_shown[v.id] = entry
	_place(entry, _camera_spot())


func _on_ended(p: Dictionary) -> void:
	var id := int(p.get("id", 0))
	if _shown.has(id):
		_drop(_shown[id])
		_shown.erase(id)


func _on_thermal(p: Dictionary) -> void:
	_thinned = float(config["thermal_share"]) if bool(p.get("on", false)) else 1.0
	var eye: Variant = _camera_spot()
	for id: int in _shown:
		_place(_shown[id], eye)


func _process(delta: float) -> void:
	if _shown.is_empty():
		return
	var t := Prof.start()
	var eye: Variant = _camera_spot()
	var gone: Array[int] = []
	for id: int in _shown:
		var entry: Dictionary = _shown[id]
		var v: SmokeVolume = entry["volume"]
		v.age += delta
		if v.ended():
			gone.append(id)
		else:
			_place(entry, eye)
	for id: int in gone:
		_drop(_shown[id])
		_shown.erase(id)
	Prof.stop(&"smoke/view", t)


func _place(entry: Dictionary, eye: Variant) -> void:
	# A thermal sight turning off as the game shuts down can reach here with the plumes
	# already leaving the tree.
	if not (entry["cloud"] as Node3D).is_inside_tree():
		return
	var v: SmokeVolume = entry["volume"]
	var centre := v.centre_at(v.age)
	var radius := v.radius_at(v.age)
	var share := v.density_at(v.age) / maxf(v.density, 0.001) * _thinned
	var fog := entry.get("fog") as FogVolume
	var use_fog := fog != null and eye is Vector3 and (eye as Vector3).distance_to(centre) + radius < _fog_length()
	if fog != null:
		fog.visible = use_fog
		fog.global_position = centre
		fog.size = Vector3.ONE * radius * 2.0
		var fm := fog.material as FogMaterial
		fm.density = float(config["fog_density"]) * share
		fm.emission = _ambient_glow()
	var cloud := entry["cloud"] as MultiMeshInstance3D
	cloud.visible = not use_fog
	cloud.global_position = centre
	cloud.scale = Vector3.ONE * radius
	var material := entry["material"] as StandardMaterial3D
	material.albedo_color.a = share


func _drop(entry: Dictionary) -> void:
	for key: String in ["fog", "cloud"]:
		var node := entry.get(key) as Node
		if is_instance_valid(node):
			node.queue_free()


func _colour() -> Color:
	var c: Array = config["colour"]
	return Color(float(c[0]), float(c[1]), float(c[2]))


func _fog_albedo() -> Color:
	var c: Array = config["fog_albedo"]
	return Color(float(c[0]), float(c[1]), float(c[2]))


## Lumpy density inside the fog volume, so a plume billows instead of being a smooth ball.
func _billows(seed_value: int) -> NoiseTexture3D:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.14
	noise.fractal_octaves = 3
	# Thin parts go to nothing and thick ones to full, so the outline breaks into lumps
	# rather than fading evenly to a round edge.
	var ramp := Gradient.new()
	ramp.set_color(0, Color.BLACK)
	ramp.set_offset(0, 0.4)
	ramp.set_color(1, Color.WHITE)
	ramp.set_offset(1, 0.7)
	var tex := NoiseTexture3D.new()
	tex.color_ramp = ramp
	tex.width = 32
	tex.height = 32
	tex.depth = 32
	tex.seamless = true
	tex.noise = noise
	return tex


func _material(_v: SmokeVolume) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = _colour()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 1.0
	return m


## Small quads scattered through a unit sphere (the node is scaled to the plume's radius),
## with gaps between them and thinner towards the edge: with alpha hash, an instance's alpha
## is the share of its pixels drawn, so a thin puff is a sparse dither rather than a solid
## square, and the cloud doesn't read as one grey block.
func _cloud(v: SmokeVolume, material: StandardMaterial3D) -> MultiMeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = v.seed
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _quad
	mm.instance_count = int(config["particles"])
	for i in mm.instance_count:
		var dir := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var out := pow(rng.randf(), 0.7)
		var size := rng.randf_range(0.3, 0.55)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), dir * out))
		var shade := rng.randf_range(0.8, 1.15)
		mm.set_instance_color(i, Color(shade, shade, shade, lerpf(0.95, 0.45, out)))
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _camera_spot() -> Variant:
	var camera := get_viewport().get_camera_3d()
	return camera.global_position if camera != null else null


## Volumetric fog only takes direct light, so a plume in the dusk or in shade turns into a
## black hole; a little of the scene's ambient light as glow keeps it the sky's colour.
func _ambient_glow() -> Color:
	var world := get_viewport().find_world_3d()
	if world == null or world.environment == null:
		return Color.BLACK
	var env := world.environment
	return env.ambient_light_color * env.ambient_light_energy * float(config["fog_ambient"])


## How far the world's volumetric fog reaches; 0 when it is off, so plumes stay particles.
func _fog_length() -> float:
	var world := get_viewport().find_world_3d()
	if world != null and world.environment != null and world.environment.volumetric_fog_enabled:
		return world.environment.volumetric_fog_length
	return 0.0
