class_name AssetLibrary
extends Control
## Browse everything the voxel kit can make: pick an asset, drag its sliders, reroll its
## seed, and see it with or without the pixel-art filter. Client only; nothing here touches
## a game session.

signal closed

const FILTER_SHADER := "res://modules/voxkit/library/pixel_filter.gdshader"
const PANEL_WIDTH := 340
const SCENE_LABEL := "Roadside scene"
const GROUND := Color(0.36, 0.42, 0.25)

var pixel_filter := false
var pixel_size := 3
var outlines := true
var levels := 14.0
## Draw models on the GPU as voxel volumes (#306) instead of as meshes.
var gpu_voxels := false

var _generators: Array[VoxGenerator] = []
var _index := 0
var _values: Dictionary = {}
var _dirty := true
var _list: ItemList
var _params: VBoxContainer
var _stats: Label
var _view: SubViewportContainer
var _viewport: SubViewport
var _models: Node3D
var _camera: OrbitCamera
var _filter: ShaderMaterial
var _post: MeshInstance3D
var _env: Environment


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_generators = VoxCatalog.all()
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 0)
	add_child(row)
	row.add_child(_side_panel())
	row.add_child(_viewport_view())
	_fill_list()
	select(0)


func _process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		_rebuild()


## Shows asset `index` from the list (the last entry is the roadside scene).
func select(index: int) -> void:
	_index = clampi(index, 0, _generators.size())
	_list.select(_index)
	_values = {} if is_scene() else _generators[_index].defaults()
	if is_scene():
		_values = {"seed": 1.0}
	_build_controls()
	_dirty = true


func is_scene() -> bool:
	return _index == _generators.size()


func set_value(key: String, value: float) -> void:
	_values[key] = value
	_build_controls()
	_dirty = true


func set_pixel_filter(on: bool) -> void:
	pixel_filter = on
	_apply_view()


## Builds now instead of next frame (for captures and tests).
func rebuild_now() -> void:
	_dirty = false
	_rebuild()


func _side_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = PANEL_WIDTH
	var style := StyleBoxFlat.new()
	style.bg_color = MainMenu.PANEL
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	scroll.add_child(col)
	col.add_child(_label("ASSET LIBRARY", 24, MainMenu.ACCENT))
	var hint := _label("Voxel models made by code. Drag to turn, wheel to zoom.", 13, MainMenu.DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(hint)
	_list = ItemList.new()
	_list.name = "Assets"
	_list.auto_height = true
	_list.item_selected.connect(select)
	col.add_child(_list)
	_stats = _label("", 13, MainMenu.DIM)
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_stats)
	col.add_child(_label("PARAMETERS", 13, MainMenu.LABEL))
	_params = VBoxContainer.new()
	_params.add_theme_constant_override("separation", 2)
	col.add_child(_params)
	var reroll := Button.new()
	reroll.text = "Reroll seed"
	reroll.pressed.connect(func() -> void: set_value("seed", float(randi_range(0, 9999))))
	col.add_child(reroll)
	var reset := Button.new()
	reset.text = "Reset to defaults"
	reset.pressed.connect(func() -> void: select(_index))
	col.add_child(reset)
	col.add_child(_label("VIEW", 13, MainMenu.LABEL))
	col.add_child(_slider_row("Colour noise", 0.0, 1.5, 0.05, VoxGenerator.colour_noise, func(v: float) -> void:
		VoxGenerator.colour_noise = v
		_dirty = true))
	col.add_child(_check("Pixel filter", pixel_filter, func(on: bool) -> void:
		pixel_filter = on
		_apply_view()))
	col.add_child(_check("Outlines", outlines, func(on: bool) -> void:
		outlines = on
		_apply_view()))
	col.add_child(_check("GPU voxels", gpu_voxels, func(on: bool) -> void:
		gpu_voxels = on
		_dirty = true))
	col.add_child(_check("Turn on its own", true, func(on: bool) -> void: _camera.turntable = on))
	col.add_child(_slider_row("Pixel size", 1.0, 8.0, 1.0, pixel_size, func(v: float) -> void:
		pixel_size = int(v)
		_apply_view()))
	col.add_child(_slider_row("Colour levels", 4.0, 48.0, 1.0, levels, func(v: float) -> void:
		levels = v
		_apply_view()))
	var back := Button.new()
	back.name = "Back"
	back.text = "Back to menu"
	back.custom_minimum_size.y = 34
	back.pressed.connect(func() -> void: closed.emit())
	col.add_child(back)
	return panel


func _viewport_view() -> Control:
	_view = SubViewportContainer.new()
	_view.stretch = true
	_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_view.gui_input.connect(func(e: InputEvent) -> void: _camera.handle(e))
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.handle_input_locally = false
	_view.add_child(_viewport)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.35, 0.5, 0.72)
	sky_mat.sky_horizon_color = Color(0.72, 0.76, 0.78)
	sky_mat.ground_horizon_color = Color(0.5, 0.52, 0.48)
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = true
	e.ssao_radius = 1.2
	e.fog_enabled = true
	e.fog_density = 0.004
	e.fog_light_color = Color(0.7, 0.75, 0.8)
	env.environment = e
	_env = e
	_viewport.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(35.0), 0.0)
	sun.light_energy = 1.3
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	_viewport.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(600, 600)
	ground.mesh = plane
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = GROUND
	ground_mat.roughness = 1.0
	ground.material_override = ground_mat
	ground.position.y = -0.01
	_viewport.add_child(ground)
	_models = Node3D.new()
	_models.name = "Models"
	_viewport.add_child(_models)
	_camera = OrbitCamera.new()
	_camera.current = true
	_camera.far = 800.0
	_viewport.add_child(_camera)
	_post = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	quad.flip_faces = true
	_post.mesh = quad
	_post.extra_cull_margin = 16384.0
	_filter = ShaderMaterial.new()
	_filter.shader = load(FILTER_SHADER)
	_post.material_override = _filter
	_camera.add_child(_post)
	_apply_view()
	return _view


func _apply_view() -> void:
	if _view == null:
		return
	_view.stretch_shrink = pixel_size if pixel_filter else 1
	_viewport.msaa_3d = Viewport.MSAA_DISABLED if pixel_filter else Viewport.MSAA_4X
	# Grainy at low resolution; soft and useful at full.
	_env.ssao_enabled = not pixel_filter
	_post.visible = pixel_filter or outlines
	_filter.set_shader_parameter("outlines", outlines)
	_filter.set_shader_parameter("posterize", pixel_filter)
	_filter.set_shader_parameter("rim_light", pixel_filter)
	_filter.set_shader_parameter("levels", levels)


func _fill_list() -> void:
	for gen in _generators:
		_list.add_item(gen.title())
	_list.add_item(SCENE_LABEL)


func _build_controls() -> void:
	for child in _params.get_children():
		child.queue_free()
	var specs: Array[Dictionary] = []
	if is_scene():
		specs.append(VoxGenerator.seed_param())
	else:
		specs = _generators[_index].params()
	for spec in specs:
		var key: String = spec["key"]
		var value := float(_values.get(key, spec["default"]))
		if spec.has("options"):
			_params.add_child(_option_row(spec, int(value)))
		else:
			_params.add_child(_slider_row(spec["label"], spec["min"], spec["max"], spec["step"], value, func(v: float) -> void:
				_values[key] = v
				_dirty = true))


func _rebuild() -> void:
	for child in _models.get_children():
		child.queue_free()
	var started := Time.get_ticks_usec()
	var voxels := 0
	var quads := 0
	var entries: Array[Array] = []
	if is_scene():
		entries = VoxCatalog.roadside(int(_values.get("seed", 1.0)))
	else:
		entries.append([_generators[_index], _values, Transform3D.IDENTITY])
	var bounds := AABB()
	var first := true
	var model: VoxelModel
	for entry: Array in entries:
		var gen: VoxGenerator = entry[0]
		model = gen.build(entry[1])
		voxels += model.voxel_count()
		var inst: MeshInstance3D
		if gpu_voxels:
			var volume := VoxelVolume.new()
			volume.model = model
			volume.refresh()
			inst = volume
		else:
			inst = MeshInstance3D.new()
			inst.mesh = VoxGenerator.to_mesh(model)
			if inst.mesh.get_surface_count() > 0:
				quads += (inst.mesh as ArrayMesh).surface_get_array_len(0) / 4
		inst.transform = entry[2]
		_models.add_child(inst)
		if inst.mesh == null:
			continue
		var box: AABB = inst.transform * inst.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	var ms := (Time.get_ticks_usec() - started) / 1000.0
	if is_scene():
		_stats.text = "%d models, %s voxels, %s faces, built in %.0f ms" % [entries.size(), _thousands(voxels), _thousands(quads), ms]
	else:
		var cells := model.cells()
		var drawn := "drawn on the GPU" if gpu_voxels else "%s faces" % _thousands(quads)
		_stats.text = "%s voxels at %.3f m (%d x %d x %d cells), %s, built in %.0f ms" % [_thousands(voxels), model.voxel_size(), cells.x, cells.y, cells.z, drawn, ms]
	if is_scene():
		# The whole scene is too wide to frame from its bounds; look down the road instead.
		_camera.target = Vector3(0, 2.0, 0)
		_camera.distance = 34.0
	else:
		_camera.frame(bounds)


static func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out


func _slider_row(label: String, lo: float, hi: float, step: float, value: float, changed: Callable) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var head := HBoxContainer.new()
	var name_label := _label(label, 13, MainMenu.TEXT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	var shown := _label(_format(value, step), 13, MainMenu.ACCENT)
	head.add_child(shown)
	box.add_child(head)
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = value
	slider.value_changed.connect(func(v: float) -> void:
		shown.text = _format(v, step)
		changed.call(v))
	box.add_child(slider)
	return box


func _option_row(spec: Dictionary, value: int) -> Control:
	var head := HBoxContainer.new()
	var name_label := _label(spec["label"], 13, MainMenu.TEXT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	var pick := OptionButton.new()
	for o: String in spec["options"]:
		pick.add_item(o)
	pick.select(value)
	var key: String = spec["key"]
	pick.item_selected.connect(func(i: int) -> void:
		_values[key] = float(i)
		_dirty = true)
	head.add_child(pick)
	return head


func _check(text: String, on: bool, toggled: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = on
	c.toggled.connect(toggled)
	return c


static func _format(v: float, step: float) -> String:
	if step >= 1.0:
		return str(int(v))
	if step >= 0.05:
		return "%.2f" % v
	return "%.3f" % v


func _label(text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	return l
