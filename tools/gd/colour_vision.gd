extends SceneTree
## Shows a capture as colour-blind players see it: writes `<out>-protan.png`, `-deutan.png`
## and `-tritan.png` (and `<out>-normal.png`, the same crop untouched) beside each other.
##   godot --headless --path . -s res://tools/gd/colour_vision.gd -- --in a.png --out b
##     [--crop x,y,w,h] [--scale N]
## `--crop` cuts a part out first and `--scale` enlarges it with hard pixel edges, so a band a
## few pixels wide can be looked at.


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var input := _arg(args, "--in")
	var output := _arg(args, "--out")
	if input.is_empty() or output.is_empty():
		push_error("usage: -- --in <png> --out <path without .png> [--crop x,y,w,h] [--scale N]")
		quit(1)
		return
	var image := Image.load_from_file(input)
	if image == null:
		push_error("could not read " + input)
		quit(1)
		return
	var crop := _arg(args, "--crop")
	if not crop.is_empty():
		var p := crop.split(",")
		image = image.get_region(Rect2i(int(p[0]), int(p[1]), int(p[2]), int(p[3])))
	var scale := maxi(1, int(_arg(args, "--scale", "1")))
	for kind: StringName in ColourVision.KINDS:
		var path := "%s-%s.png" % [output, kind]
		var seen := ColourVision.simulate_image(image, kind)
		if scale > 1:
			seen.resize(seen.get_width() * scale, seen.get_height() * scale, Image.INTERPOLATE_NEAREST)
		if seen.save_png(path) != OK:
			push_error("could not write " + path)
			quit(1)
			return
		print(path)
	quit(0)


func _arg(args: PackedStringArray, name: String, fallback := "") -> String:
	var i := args.find(name)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else fallback
