extends SceneTree
## Renders a capture setup and saves frames as one PNG contact sheet. Needs a real
## renderer, so tools/capture.ts runs it windowed with --fixed-fps for repeatable frames.
## Args after `--`: --setup <res://script extending Node> --out <path.png> --frames N --sheet K


class Capturer:
	extends Node

	var out_path: String
	var total_frames: int
	var sheet_count: int
	var _frame := 0
	var _grab_at: Array[int] = []
	var _images: Array[Image] = []

	func _ready() -> void:
		for i in sheet_count:
			# Evenly spaced, always including the last frame.
			_grab_at.append(int(round(float(total_frames) * float(i + 1) / float(sheet_count))))

	func _process(_delta: float) -> void:
		_frame += 1
		if _frame in _grab_at:
			await RenderingServer.frame_post_draw
			_images.append(get_viewport().get_texture().get_image())
			if _images.size() == sheet_count:
				_save()
				get_tree().quit(0)

	func _save() -> void:
		var cols := mini(3, sheet_count)
		var rows := ceili(float(sheet_count) / cols)
		var cell := Vector2i(640, 360) if sheet_count > 1 else _images[0].get_size()
		var sheet := Image.create(cell.x * cols, cell.y * rows, false, Image.FORMAT_RGBA8)
		for i in _images.size():
			var img := _images[i]
			img.convert(Image.FORMAT_RGBA8)
			img.resize(cell.x, cell.y, Image.INTERPOLATE_BILINEAR)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, cell), Vector2i((i % cols) * cell.x, (i / cols) * cell.y))
		var err := sheet.save_png(out_path)
		if err != OK:
			push_error("capture: could not save %s (%s)" % [out_path, error_string(err)])
		else:
			print("capture: saved %s (%d frame(s))" % [out_path, _images.size()])


func _initialize() -> void:
	var args := _parse(OS.get_cmdline_user_args())
	var setup_script: Variant = load(args.get("setup", ""))
	if not setup_script is GDScript:
		push_error("capture: --setup must be a GDScript path, got '%s'" % args.get("setup", ""))
		quit(1)
		return
	var setup: Node = (setup_script as GDScript).new()
	root.add_child(setup)
	var capturer := Capturer.new()
	capturer.out_path = args.get("out", "user://capture.png")
	capturer.total_frames = int(args.get("frames", "60"))
	capturer.sheet_count = int(args.get("sheet", "1"))
	root.add_child(capturer)


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
