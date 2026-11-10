extends SceneTree
## One trailer shot through Godot's Movie Maker: tools/trailer.ts runs it with
## `--write-movie <file.avi> --fixed-fps N`, so every frame is rendered and written no matter
## how slow it is. Either plays a capture setup (`--setup res://...`) or shows a title card
## (`--title "text"`, optional `--subtitle "text"`). Quits after `--frames N`. `--hud off`
## hides the game's HUD layers (prompts, mission lines) for clean shots; screens such as
## the loot screen stay.

## Canvas layers at or below this are HUD (prompts, mission lines, health); higher ones are
## screens.
const HUD_LAYER_MAX := 10
const BG := Color(0.07, 0.08, 0.07)
const ACCENT := Color(0.86, 0.64, 0.3)
const TEXT := Color(0.9, 0.9, 0.86)


class Clock:
	extends Node

	var frames := 60
	var hide_hud := false
	var _frame := 0

	func _process(_delta: float) -> void:
		if hide_hud:
			_hide(get_tree().root)
		_frame += 1
		if _frame >= frames:
			get_tree().quit(0)

	func _hide(node: Node) -> void:
		for child in node.get_children():
			if child is CanvasLayer and (child as CanvasLayer).layer <= HUD_LAYER_MAX and not child.has_meta(&"title_card"):
				(child as CanvasLayer).visible = false
			_hide(child)


func _initialize() -> void:
	var args := _parse(OS.get_cmdline_user_args())
	var clock := Clock.new()
	clock.frames = int(args.get("frames", "60"))
	clock.hide_hud = str(args.get("hud", "on")) == "off"
	if args.has("title"):
		root.add_child(_title_card(str(args["title"]), str(args.get("subtitle", ""))))
	else:
		var setup_script: Variant = load(args.get("setup", ""))
		if not setup_script is GDScript:
			push_error("movie: --setup must be a GDScript path, got '%s'" % args.get("setup", ""))
			quit(1)
			return
		root.add_child((setup_script as GDScript).new())
	root.add_child(clock)


func _title_card(title: String, subtitle: String) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.set_meta(&"title_card", true)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	layer.add_child(box)
	box.add_child(_label(title, 96, ACCENT))
	if not subtitle.is_empty():
		box.add_child(_label(subtitle, 36, TEXT))
	return layer


func _label(text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	return l


func _parse(argv: PackedStringArray) -> Dictionary:
	var out := {}
	var i := 0
	while i < argv.size() - 1:
		if argv[i].begins_with("--"):
			out[argv[i].trim_prefix("--")] = argv[i + 1]
			i += 2
		else:
			i += 1
	return out
