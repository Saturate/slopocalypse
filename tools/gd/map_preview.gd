extends SceneTree
## Renders a map recipe top-down to a PNG (MapRender), for tools/map-preview.ts and
## tools/map-viewer.ts:
##   godot --headless --path . -s res://tools/gd/map_preview.gd -- <recipe path> <seed> <out png> <pixels> [layers] [stats json]
## `layers` is comma separated (all when left out); `stats json` gets the summary and the
## hover grid. No rendering server needed.


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 4:
		push_error("map_preview: want <recipe> <seed> <out> <pixels>")
		quit(2)
		return
	var file := FileAccess.open(args[0], FileAccess.READ)
	if file == null:
		push_error("map_preview: no recipe at %s" % args[0])
		quit(2)
		return
	var recipe: Variant = JSON.parse_string(file.get_as_text())
	if not recipe is Dictionary:
		push_error("map_preview: %s is not a JSON object" % args[0])
		quit(2)
		return
	var pixels := maxi(int(args[3]), 16)
	var layers := (args[4] if args.size() > 4 else MapRender.ALL_LAYERS).split(",", false)
	var view := MapRender.make(recipe, int(args[1]), pixels, layers)
	var image: Image = view["image"]
	if args.size() > 5:
		var out := FileAccess.open(args[5], FileAccess.WRITE)
		if out == null:
			push_error("map_preview: could not write %s" % args[5])
			quit(1)
			return
		# Keys in the order written: the summary reads top to bottom as it was built.
		out.store_string(JSON.stringify(view["stats"], "", false))
	var err := image.save_png(args[2])
	if err != OK:
		push_error("map_preview: could not write %s (%d)" % [args[2], err])
		quit(1)
		return
	print("map_preview: wrote %s (%d px)" % [args[2], pixels])
	quit(0)
