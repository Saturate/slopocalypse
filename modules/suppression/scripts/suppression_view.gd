class_name SuppressionView
extends CanvasLayer
## Client only, the local player under fire: the screen edges darken toward the middle with
## their suppression, and each near miss gives the view a short shake (unless the "Screen
## shake under fire" setting is off). Under the HUD, so health, ammo and the crosshair stay
## readable; the middle of the screen is never touched and the edges never go fully black.
## Purely what you see: the module sets `level` and calls `near_miss`. It owns the camera's
## own rotation (aim turns the head above it), resetting it to zero once a shake is over.

const SETTING := "shake_under_fire"
## Never a black screen, whatever the data says.
const MAX_ALPHA := 0.95

var config: Dictionary = {}
var camera: Camera3D
## 0 to 1, the local player's suppression now.
var level := 0.0
## The view's usual field of view: zoomed in further (a scope), the shake turns the camera
## less, so it moves the picture about as much as from the hip.
var base_fov := 80.0

var _canvas := Control.new()
var _edges: GradientTexture2D
var _shake_left := 0.0
var _shake_strength := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	layer = UiLayers.EFFECTS
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw)
	add_child(_canvas)
	_edges = edge_texture()


## A radial fade from clear (out to `clear_share` of the way to a corner) to black at the
## corners; drawn at `edge_alpha()`.
func edge_texture() -> GradientTexture2D:
	if _edges != null:
		return _edges
	var g := Gradient.new()
	g.set_color(0, Color(0.0, 0.0, 0.0, 0.0))
	g.set_color(1, Color(0.0, 0.0, 0.0, 1.0))
	var clear := float(_vignette().get("clear_share", 0.25))
	g.set_offset(0, clear)
	# Most of the screen's edge lies well short of the corners: darken quickly past the clear
	# middle, so the edges read as dark too and not only the corners.
	g.add_point(lerpf(clear, 1.0, 0.45), Color(0.0, 0.0, 0.0, 0.75))
	var texture := GradientTexture2D.new()
	texture.gradient = g
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	# The gradient's end at the corners, so the full darkness is only there.
	texture.fill_to = Vector2(1.0, 1.0)
	_edges = texture
	return texture


func edge_alpha() -> float:
	return clampf(level, 0.0, 1.0) * minf(float(_vignette().get("max_alpha", 0.85)), MAX_ALPHA)


## A round just went past: shake, harder the more suppressed you already are.
func near_miss() -> void:
	if not bool(Settings.value(SETTING)):
		return
	_shake_left = float(_shake_cfg().get("seconds", 0.25))
	_shake_strength = deg_to_rad(float(_shake_cfg().get("degrees", 0.6))) * clampf(0.4 + 0.6 * level, 0.0, 1.0)


func _process(delta: float) -> void:
	var prof := Prof.start()
	_process_tick(delta)
	Prof.stop(&"suppression/view:frame", prof)


func _process_tick(delta: float) -> void:
	_canvas.visible = level > 0.0
	if level > 0.0:
		_canvas.queue_redraw()
	if camera == null or not is_instance_valid(camera):
		return
	# Switched off mid-shake: back to steady at once.
	if _shake_left > 0.0 and not bool(Settings.value(SETTING)):
		_shake_left = 0.0
	if _shake_left <= 0.0:
		if camera.rotation != Vector3.ZERO:
			camera.rotation = Vector3.ZERO
		return
	_shake_left = maxf(_shake_left - delta, 0.0)
	var fade := _shake_left / maxf(float(_shake_cfg().get("seconds", 0.25)), 0.01)
	var amount := _shake_strength * fade * clampf(camera.fov / maxf(base_fov, 1.0), 0.0, 1.0)
	camera.rotation = Vector3(_rng.randf_range(-amount, amount), _rng.randf_range(-amount, amount), _rng.randf_range(-amount, amount) * 0.5)


func _draw() -> void:
	var alpha := edge_alpha()
	if alpha > 0.0:
		_canvas.draw_texture_rect(_edges, Rect2(Vector2.ZERO, _canvas.size), false, Color(1, 1, 1, alpha))


func _vignette() -> Dictionary:
	var v: Variant = config.get("vignette", {})
	return v if v is Dictionary else {}


func _shake_cfg() -> Dictionary:
	var v: Variant = config.get("shake", {})
	return v if v is Dictionary else {}
