class_name ModdingScreen
extends CanvasLayer
## Client only, local player: the weapon modding screen (B). A turning preview of the gun,
## a part picker per slot, the stats of the new build against the current one, and Apply,
## which asks the server to make it this player's gun. Parts are swapped on a draft; nothing
## changes until the server accepts. Every part is offered until inventory exists.

const BG := Color(0.05, 0.06, 0.06, 0.82)
const PANEL := Color(0.11, 0.12, 0.11, 0.97)
const ACCENT := Color(0.82, 0.62, 0.3)
const TEXT := Color(0.86, 0.86, 0.82)
const DIM := Color(0.6, 0.61, 0.58)
const BETTER := Color(0.45, 0.85, 0.45)
const WORSE := Color(0.95, 0.42, 0.35)
const PREVIEW_SIZE := Vector2i(560, 360)
const TURN_SPEED := 0.35
const NONE := "(none)"

var weapons: Node
var player: PlayerController
var peer := 1

var _root: Control
var _preview_port: SubViewport
var _preview_pivot: Node3D
var _preview_gun: Node3D
var _pickers: Dictionary[String, OptionButton] = {}
var _stats_grid: GridContainer
var _parts_grid: GridContainer
var _title: Label
var _slot_labels: Dictionary[String, Label] = {}
var _errors: Label
var _apply: Button
var _current: Dictionary = {}
var _draft: Dictionary = {}


func _ready() -> void:
	layer = 40
	_build_ui()
	_root.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"modding"):
		toggle()
		get_viewport().set_input_as_handled()
	elif is_open() and event is InputEventKey and event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if is_open() and _preview_pivot != null:
		_preview_pivot.rotate_y(TURN_SPEED * delta)


func is_open() -> bool:
	return _root.visible


func toggle() -> void:
	if is_open():
		close()
	else:
		open()


func open() -> void:
	var slot: String = weapons.call(&"drawn_slot", player)
	_current = weapons.call(&"build_of", int(player.get_meta(&"peer_id", 1)), slot)
	_draft = _current.duplicate()
	_fill_pickers()
	_root.visible = true
	_preview_port.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()


func close() -> void:
	_root.visible = false
	_preview_port.render_target_update_mode = SubViewport.UPDATE_DISABLED
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Puts `part_id` ("" for none) in `slot` on the draft.
func select(slot: String, part_id: String) -> void:
	_draft = GunModding.with_part(_draft, slot, part_id)
	_refresh()


func load_preset(build_name: String) -> void:
	var preset := GunAssembly.build(build_name)
	# A preset for the other weapon (a pistol while the rifle is out) does not apply here.
	if str(preset.get("receiver", "")) != str(_current.get("receiver", "")):
		return
	_draft = preset.duplicate()
	_refresh()


func apply() -> void:
	var result := WeaponBuild.assemble(GunAssembly.catalogue(), _draft)
	if not result["ok"]:
		return
	weapons.call(&"request_build", _draft.duplicate())
	close()


## Parts offered for `slot`: what is fitted now plus what the inventory holds (every part
## when there is no inventory module).
func owned_options(slot: String) -> Array[String]:
	var inv: Node = weapons.call(&"inventory")
	var out: Array[String] = []
	for id in GunModding.options(slot):
		if inv == null or id == str(_current.get(slot, "")) or int(inv.call(&"count", peer, id)) > 0:
			out.append(id)
	return out


func draft() -> Dictionary:
	return _draft


## Rows of {label, before, after, verdict} as shown, for tests.
func shown_stats() -> Array[Dictionary]:
	var current := WeaponBuild.assemble(GunAssembly.catalogue(), _current)
	var next := WeaponBuild.assemble(GunAssembly.catalogue(), _draft)
	if not current["ok"] or not next["ok"]:
		return []
	return GunModding.compare(current["stats"], next["stats"])


func _refresh() -> void:
	for slot: String in _pickers:
		var picker := _pickers[slot]
		var available := GunModding.is_available(slot, _draft)
		picker.disabled = not available or GunModding.options(slot).size() <= 1 and GunModding.is_required(slot, _draft) or slot == "receiver"
		var fitted := str(_draft.get(slot, ""))
		for i in picker.item_count:
			if str(picker.get_item_metadata(i)) == fitted:
				picker.select(i)
	var result := WeaponBuild.assemble(GunAssembly.catalogue(), _draft)
	_apply.disabled = not result["ok"] or _draft == _current
	_errors.text = "" if result["ok"] else "\n".join(result["errors"])
	_errors.visible = not result["ok"]
	for child in _stats_grid.get_children():
		_stats_grid.remove_child(child)
		child.queue_free()
	for head in ["", "Now", "New", "Change"]:
		_stats_grid.add_child(_label(head, 13, DIM))
	for row in shown_stats():
		# Unchanged rows step back so the eye goes to what the parts changed.
		var same: bool = row["verdict"] == 0
		var colour := DIM if same else (BETTER if row["verdict"] > 0 else WORSE)
		_stats_grid.add_child(_label(row["label"], 14, DIM if same else TEXT))
		_stats_grid.add_child(_label(row["before"], 14, DIM if same else TEXT))
		_stats_grid.add_child(_label(row["after"], 14, colour))
		_stats_grid.add_child(_label(row["delta"], 14, colour))
	_title.text = _build_title()
	for slot: String in _pickers:
		var changed := str(_draft.get(slot, "")) != str(_current.get(slot, ""))
		_slot_labels[slot].text = ("> " if changed else "") + slot.capitalize()
		_slot_labels[slot].add_theme_color_override("font_color", ACCENT if changed else TEXT)
	if _preview_gun != null:
		_preview_pivot.remove_child(_preview_gun)
		_preview_gun.queue_free()
	_preview_gun = GunAssembly.build_model(_draft)
	# Centred on its middle so it turns in place.
	_preview_gun.position = Vector3(0, -0.02, 0.14)
	_preview_pivot.add_child(_preview_gun)


## One row per slot this gun can have (a rifle and a pistol have different ones), built
## when the screen opens on the drawn gun.
func _fill_pickers() -> void:
	for child in _parts_grid.get_children():
		_parts_grid.remove_child(child)
		child.queue_free()
	_pickers.clear()
	_slot_labels.clear()
	for slot in GunModding.slots_for(_current):
		var slot_label := _label(slot.capitalize(), 15, TEXT)
		slot_label.custom_minimum_size.x = 130
		_slot_labels[slot] = slot_label
		_parts_grid.add_child(slot_label)
		var picker := OptionButton.new()
		picker.name = "Pick_" + slot
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not GunModding.is_required(slot, _current):
			picker.add_item(NONE)
			picker.set_item_metadata(0, "")
		var choices := owned_options(slot)
		if slot == "receiver":
			choices = [str(_current["receiver"])]
		for id in choices:
			picker.add_item(GunModding.display_name(id))
			picker.set_item_metadata(picker.item_count - 1, id)
		picker.item_selected.connect(func(i: int) -> void: select(slot, str(picker.get_item_metadata(i))))
		_parts_grid.add_child(picker)
		_pickers[slot] = picker


## The preset's name when the draft is one, otherwise a custom build.
func _build_title() -> String:
	for build_name: String in GunAssembly.build_names():
		if GunAssembly.build(build_name) == _draft:
			return build_name.to_upper().replace("_", " ")
	return "CUSTOM BUILD"


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = BG
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = ACCENT.darkened(0.5)
	style.border_width_top = 3
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	panel.add_child(row)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	row.add_child(left)
	_title = _label("", 26, ACCENT)
	left.add_child(_title)
	left.add_child(_preview())
	_stats_grid = GridContainer.new()
	_stats_grid.columns = 4
	_stats_grid.add_theme_constant_override("h_separation", 26)
	_stats_grid.add_theme_constant_override("v_separation", 0)
	left.add_child(_stats_grid)

	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 380
	right.add_theme_constant_override("separation", 6)
	row.add_child(right)
	right.add_child(_label("PRESETS", 13, DIM))
	var presets := OptionButton.new()
	presets.name = "Presets"
	presets.add_item("Load a preset...")
	for build_name: String in GunAssembly.build_names():
		presets.add_item(build_name)
		presets.set_item_metadata(presets.item_count - 1, build_name)
	presets.item_selected.connect(func(i: int) -> void:
		if i > 0:
			load_preset(str(presets.get_item_metadata(i)))
		presets.select(0))
	right.add_child(presets)
	right.add_child(_label("PARTS", 13, DIM))
	_parts_grid = GridContainer.new()
	_parts_grid.columns = 2
	_parts_grid.add_theme_constant_override("h_separation", 12)
	_parts_grid.add_theme_constant_override("v_separation", 3)
	right.add_child(_parts_grid)
	_errors = _label("", 14, WORSE)
	_errors.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_errors)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)
	right.add_child(_label("Parts come from your backpack (Tab); removed ones go back in it.
Swapping parts empties the magazine.", 13, DIM))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	right.add_child(buttons)
	_apply = _button("Apply", apply, true)
	buttons.add_child(_apply)
	buttons.add_child(_button("Reset", func() -> void:
		_draft = _current.duplicate()
		_refresh()))
	buttons.add_child(_button("Close", close))


## The turning gun on a plain backdrop in its own world, so the game's world and lights do
## not show behind it.
func _preview() -> Control:
	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(PREVIEW_SIZE)
	container.stretch = true
	_preview_port = SubViewport.new()
	_preview_port.own_world_3d = true
	_preview_port.size = PREVIEW_SIZE
	_preview_port.render_target_update_mode = SubViewport.UPDATE_DISABLED
	container.add_child(_preview_port)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.36, 0.38, 0.4)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.61, 0.63)
	_preview_port.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 30, 0)
	key.light_energy = 1.2
	_preview_port.add_child(key)
	# A rim from behind picks the dark metal out of the backdrop.
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, 200, 0)
	rim.light_energy = 0.8
	_preview_port.add_child(rim)
	_preview_pivot = Node3D.new()
	_preview_port.add_child(_preview_pivot)
	var camera := Camera3D.new()
	camera.fov = 32.0
	camera.position = Vector3(0, 0.06, 1.45)
	camera.rotation.x = -0.08
	_preview_port.add_child(camera)
	camera.current = true
	return container


func _label(text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	return l


func _button(text: String, on_press: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.name = text
	b.text = text
	b.custom_minimum_size = Vector2(100, 38)
	if primary:
		var st := StyleBoxFlat.new()
		st.bg_color = ACCENT.darkened(0.15)
		st.set_corner_radius_all(2)
		b.add_theme_stylebox_override("normal", st)
		b.add_theme_color_override("font_color", Color(0.07, 0.08, 0.08))
	b.pressed.connect(on_press)
	return b
