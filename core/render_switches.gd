class_name RenderSwitches
extends RefCounted
## Command-line switches that take rendering work away, so a benchmark can measure what that
## work costs (tools/bench.ts --ablate). Players never need them.
##   --no-shadows        no light casts shadows (the daytime sun, the lights module's lamps)
##   --render-scale=0.5  the 3D view renders at this fraction of the window and is scaled up

const NO_SHADOWS := "--no-shadows"
const RENDER_SCALE := "--render-scale="
const MIN_SCALE := 0.25
const MAX_SCALE := 2.0


static func no_shadows(args: PackedStringArray) -> bool:
	return args.has(NO_SHADOWS)


static func render_scale(args: PackedStringArray) -> float:
	for arg in args:
		if not arg.begins_with(RENDER_SCALE):
			continue
		var value := arg.trim_prefix(RENDER_SCALE)
		if not value.is_valid_float():
			Log.warn(&"render", "%s%s is not a number; rendering at full scale" % [RENDER_SCALE, value])
			return 1.0
		return clampf(value.to_float(), MIN_SCALE, MAX_SCALE)
	return 1.0


## Puts the render scale on `viewport` (the main window's at boot).
static func apply(viewport: Viewport, args: PackedStringArray) -> void:
	var scale := render_scale(args)
	if not is_equal_approx(scale, 1.0):
		viewport.scaling_3d_scale = scale
