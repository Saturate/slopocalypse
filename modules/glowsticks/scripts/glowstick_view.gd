class_name GlowstickView
extends Node
## Client: draws the glowsticks the server says are lit (`glowsticks.state`): a bright stick
## on the carrier's chest in their band colour with a small light, and sticks lying on the
## ground. Carriers are found by their `peer_id` meta, so a soldier who comes into range
## later (net relevance) gets theirs as soon as it appears. Only the `max_lights` nearest
## the camera light anything; the rest still glow.

## Seconds between looking for carriers and sorting the lights.
const REFRESH_SECONDS := 0.25
const STICK := "Glowstick"
const CHEST_BONE := "Chest"
## Where the stick sits on a body without a skeleton, metres up from the feet.
const CHEST_HEIGHT := 1.3

var config: Dictionary = {}

## Last state from the server, and when it came (msec).
var carriers: Dictionary = {}
var ground: Array = []
var _received_msec := 0
## Peer id -> the stick node on that carrier.
var _sticks: Dictionary[int, Node3D] = {}
## Ground stick id -> its node.
var _ground_nodes: Dictionary[int, Node3D] = {}
var _refresh_in := 0.0
var _hud: GlowstickHud
static var _materials: Dictionary = {}


func _ready() -> void:
	EventBus.subscribe(&"glowsticks.state", _on_state)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"glowsticks.state", _on_state)


## A stick mesh `colour`ed, glowing `glow` (0: a spare one, not lit).
static func stick(cfg: Dictionary, colour: Color, glow: float) -> MeshInstance3D:
	var size: Array = (cfg.get("stick", {}) as Dictionary).get("size", [0.03, 0.15])
	var box := BoxMesh.new()
	box.size = Vector3(float(size[0]), float(size[1]), float(size[0]))
	box.material = _material(colour, glow)
	var mesh := MeshInstance3D.new()
	mesh.name = "Stick"
	mesh.mesh = box
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.layers = RenderLayers.DEFAULT | RenderLayers.NO_DECALS
	return mesh


static func _material(colour: Color, glow: float) -> StandardMaterial3D:
	var key := "%s/%.2f" % [colour.to_html(false), glow]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = colour.lightened(0.3) if glow > 0.0 else colour
	m.roughness = 0.4
	if glow > 0.0:
		# Emission past 1 is what blooms and reads from afar in the dark.
		m.emission_enabled = true
		m.emission = colour
		m.emission_energy_multiplier = glow
	_materials[key] = m
	return m


## The local player's own count and timer, bottom left.
func show_hud_for(player: Node3D) -> void:
	if _hud == null:
		_hud = GlowstickHud.new()
		_hud.name = "Hud"
		_hud.view = self
		add_child(_hud)
	_hud.player = player


## Seconds left on `peer`'s lit stick now, and whether it is out, or {} when none is lit.
func lit_of(peer: int) -> Dictionary:
	var c: Variant = carriers.get(peer)
	if not c is Array:
		return {}
	var elapsed := (Time.get_ticks_msec() - _received_msec) / 1000.0
	return {"shown": bool(c[0]), "left": maxf(float(c[1]) - elapsed, 0.0)}


func _on_state(state: Dictionary) -> void:
	carriers = state.get("carriers", {})
	ground = state.get("ground", [])
	_received_msec = Time.get_ticks_msec()
	_refresh_in = 0.0


func _process(delta: float) -> void:
	_refresh_in -= delta
	if _refresh_in > 0.0:
		return
	_refresh_in = REFRESH_SECONDS
	var prof := Prof.start()
	refresh()
	Prof.stop(&"glowsticks/view", prof)


## Puts sticks on whoever shows one now and takes them off everyone else; the same for the
## ground; then lights only the nearest.
func refresh() -> void:
	var people := {}
	for group: StringName in [&"players", &"enemies"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			people[int(node.get_meta(&"peer_id", 0))] = node
	var wanted: Dictionary[int, bool] = {}
	for peer: Variant in carriers:
		var c: Array = carriers[peer]
		var person := people.get(int(peer)) as Node3D
		if bool(c[0]) and person != null and not person.get_meta(&"dead", false):
			wanted[int(peer)] = true
			if not is_instance_valid(_sticks.get(int(peer))):
				_sticks[int(peer)] = _attach(person, int(peer) == multiplayer.get_unique_id())
	for peer: int in _sticks.keys():
		if not wanted.has(peer) or not is_instance_valid(_sticks[peer]):
			if is_instance_valid(_sticks[peer]):
				_sticks[peer].queue_free()
			_sticks.erase(peer)
	var on_ground: Dictionary[int, bool] = {}
	for g: Variant in ground:
		var entry: Array = g
		var id := int(entry[0])
		on_ground[id] = true
		if not _ground_nodes.has(id):
			_ground_nodes[id] = _lay(entry[1] as Vector3, entry[2] as Color)
	for id: int in _ground_nodes.keys():
		if not on_ground.has(id):
			_ground_nodes[id].queue_free()
			_ground_nodes.erase(id)
	_budget_lights()


func _attach(person: Node3D, own: bool) -> Node3D:
	var colour := GlowstickRules.colour_for(person)
	var skeleton := person.get_node_or_null("Body/Skeleton") as Skeleton3D
	var holder: Node3D
	if skeleton != null and skeleton.find_bone(CHEST_BONE) >= 0:
		var bone := BoneAttachment3D.new()
		bone.bone_name = CHEST_BONE
		skeleton.add_child(bone)
		holder = bone
	else:
		holder = Node3D.new()
		holder.position.y = CHEST_HEIGHT
		person.add_child(holder)
	holder.name = STICK
	var cfg: Dictionary = config["stick"]
	var at: Array = cfg.get("at", [0.0, 0.0, 0.0])
	var mesh := stick(config, colour, float(cfg.get("glow", 4.0)))
	mesh.position = Vector3(float(at[0]), float(at[1]), float(at[2]))
	# Clipped to the strap at a slant, like it was pushed through a loop.
	mesh.rotation.z = deg_to_rad(-15.0)
	# Your own would sit at the edge of the view as a bright smear; others see it.
	if own:
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	holder.add_child(mesh)
	var light := _light(colour)
	# Out in front of the vest, so the light falls on the ground and people round them.
	light.position = mesh.position + Vector3(0.0, 0.0, -0.1)
	holder.add_child(light)
	return holder


func _lay(at: Vector3, colour: Color) -> Node3D:
	var node := Node3D.new()
	node.name = "Ground%s" % STICK
	add_child(node)
	node.global_position = at
	var mesh := stick(config, colour, float((config["stick"] as Dictionary).get("glow", 4.0)))
	var size: Array = (config["stick"] as Dictionary).get("size", [0.03, 0.15])
	mesh.rotation.x = PI / 2.0
	mesh.position.y = float(size[0]) / 2.0
	node.add_child(mesh)
	var light := _light(colour)
	light.position.y = 0.2
	node.add_child(light)
	return node


func _light(colour: Color) -> OmniLight3D:
	var cfg: Dictionary = config["light"]
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = colour
	light.light_energy = float(cfg.get("energy", 0.6))
	light.omni_range = float(cfg.get("range", 3.0))
	light.shadow_enabled = false
	return light


func _budget_lights() -> void:
	var lights: Array[OmniLight3D] = []
	for node: Node3D in _sticks.values():
		var l := node.get_node_or_null("Light") as OmniLight3D
		if l != null:
			lights.append(l)
	for node: Node3D in _ground_nodes.values():
		var l := node.get_node_or_null("Light") as OmniLight3D
		if l != null:
			lights.append(l)
	var limit := int((config["light"] as Dictionary).get("max_lights", 8.0))
	var camera := get_viewport().get_camera_3d()
	if lights.size() > limit and camera != null:
		var eye := camera.global_position
		lights.sort_custom(func(a: OmniLight3D, b: OmniLight3D) -> bool: return a.global_position.distance_squared_to(eye) < b.global_position.distance_squared_to(eye))
	for i in lights.size():
		lights[i].visible = i < limit
