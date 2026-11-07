class_name ScopeView
extends CanvasLayer
## Client only, for the local player's magnified optic: once the scope is up to the eye the
## whole view is zoomed by the magnification (the camera reads the sight's zoom) and this
## draws the scope picture over it: black outside a round lens, a crisp duplex reticle with
## a lit centre dot, a soft rim. The gun model hides while it is up, since the eyepiece
## would fill a zoomed view.

## The scope picture fades in over the last part of raising the gun.
const SHOW_FROM := 0.75
## Lens radius as a share of the screen height.
const LENS := 0.47
const LINE := 1.5
const POST := 7.0
## Posts start this far out from the centre, as a share of the lens radius.
const POST_FROM := 0.32
const DOT := 2.6
const DOT_COLOUR := Color(1.0, 0.18, 0.12)

var player: PlayerController
var gun: Node3D

var _canvas: Control
var _animator: PlayerBodyAnimator
var _shown := 0.0


func _ready() -> void:
	layer = 5
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_scope)
	add_child(_canvas)


func _process(_delta: float) -> void:
	if not is_instance_valid(gun):
		queue_free()
		return
	# Looked up late: the player module may add the animator after weapons equip the gun.
	if _animator == null:
		_animator = player.get_node_or_null("BodyAnimator") as PlayerBodyAnimator
	var ads := _animator.ads_amount() if _animator != null else 0.0
	_shown = shown_for(ads)
	gun.visible = _shown < 0.5
	_canvas.visible = _shown > 0.0
	_canvas.queue_redraw()


func _exit_tree() -> void:
	if is_instance_valid(gun):
		gun.visible = true


## How much of the scope picture shows for an ADS amount, 0 to 1.
static func shown_for(ads: float) -> float:
	return clampf((ads - SHOW_FROM) / (1.0 - SHOW_FROM), 0.0, 1.0)


func is_up() -> bool:
	return _shown >= 0.5


func _draw_scope() -> void:
	var size := _canvas.size
	var c := size / 2.0
	var r := size.y * LENS
	var a := _shown
	var black := Color(0, 0, 0, a)
	# Everything outside the lens: bands left and right of its square, then a thick ring
	# that covers the square's corners.
	_canvas.draw_rect(Rect2(0, 0, c.x - r, size.y), black)
	_canvas.draw_rect(Rect2(c.x + r, 0, size.x - c.x - r, size.y), black)
	var ring := r * 0.5
	_canvas.draw_arc(c, r + ring / 2.0, 0.0, TAU, 128, black, ring, true)
	# A soft dark rim inside the lens edge, like a real eyepiece.
	for i in 6:
		var t := float(i) / 6.0
		_canvas.draw_arc(c, r - t * r * 0.08, 0.0, TAU, 128, Color(0, 0, 0, a * (0.45 - t * 0.07)), r * 0.016, true)
	var ink := Color(0.02, 0.02, 0.02, a)
	# Fine cross through the middle, heavy posts from the edge inward.
	_canvas.draw_line(Vector2(c.x - r, c.y), Vector2(c.x + r, c.y), ink, LINE, true)
	_canvas.draw_line(Vector2(c.x, c.y - r), Vector2(c.x, c.y + r), ink, LINE, true)
	var from := r * POST_FROM
	for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN, Vector2.UP]:
		_canvas.draw_line(c + d * from, c + d * r, ink, POST, false)
	_canvas.draw_circle(c, DOT + 1.2, Color(0, 0, 0, a * 0.6))
	_canvas.draw_circle(c, DOT, Color(DOT_COLOUR, a))
