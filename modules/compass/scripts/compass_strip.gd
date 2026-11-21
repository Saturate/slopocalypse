class_name CompassStrip
extends CanvasLayer
## Client only, local player (#455): a band across the top of the screen showing the half of
## the world in front of the camera, with N, E, S and W, a tick every `tick_degrees`, and a
## marker for each thing worth finding, slid along by its bearing with its distance under it.
## A marker past an edge sticks to that edge with an arrow pointing out; one close by fades
## out, since you can see the thing itself. Off in Settings ("compass").
##
## What it shows: the base (the world's spawn, given by the module), the other players (their
## names come with their spawn), and anything another module puts in the `compass_markers`
## group: a Node3D with a `compass_kind` meta ("objective", "car", ...) and, optionally, a
## `compass_label` meta. Hidden nodes are skipped. See docs/decisions/0013.

const GROUP := &"compass_markers"
const KIND_META := &"compass_kind"
const LABEL_META := &"compass_label"
const LETTERS := {0: "N", 90: "E", 180: "S", 270: "W"}

var config: Dictionary = {}
## The local player; the strip draws nothing without one.
var player: Node3D

var _canvas: Control
var _base := Vector3.ZERO
var _has_base := false
var _plate: SteelPlate
var _items: Array[Dictionary] = []
var _heading := 0.0


func _ready() -> void:
	layer = UiLayers.HUD
	_canvas = Control.new()
	_canvas.name = "Canvas"
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw)
	add_child(_canvas)
	_plate = SteelPlate.new()
	_plate.fill = Color(UiPalette.STEEL, float(config.get("opacity", 0.9)))
	_plate.rivets = false
	_plate.shadow = Vector2(3, 3)
	_plate.bevel = 2.0


## Where the base is (the players' camp at the world's spawn).
func set_base(at: Vector3) -> void:
	_base = at
	_has_base = true


func _process(_delta: float) -> void:
	var prof := Prof.start()
	visible = bool(Settings.value("compass"))
	if visible:
		_items = items()
		_canvas.queue_redraw()
	Prof.stop(&"compass/strip:frame", prof)


## What the strip shows now, left to right as found: {kind, label, distance, x (-1 left edge
## to 1 right edge), clamped (stuck to an edge), alpha}. Empty without a camera or player.
func items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var camera := get_viewport().get_camera_3d()
	if camera == null or player == null or not is_instance_valid(player):
		return out
	var origin := camera.global_position
	_heading = CompassMath.heading(camera.global_basis)
	var found: Array[Dictionary] = []
	if _has_base:
		found.append({"kind": "base", "label": "", "at": _base})
	for other: Node in get_tree().get_nodes_in_group(&"players"):
		if other != player and other is Node3D and (other as Node3D).is_visible_in_tree():
			found.append({"kind": "partner", "label": str(other.get_meta(&"player_name", "")), "at": (other as Node3D).global_position})
	for node: Node in get_tree().get_nodes_in_group(GROUP):
		if node is Node3D and (node as Node3D).is_visible_in_tree() and node.has_meta(KIND_META):
			found.append({"kind": str(node.get_meta(KIND_META)), "label": str(node.get_meta(LABEL_META, "")), "at": (node as Node3D).global_position})
	var span := float(config.get("span_degrees", 180.0))
	for f: Dictionary in found:
		var at: Vector3 = f["at"]
		var distance := origin.distance_to(at)
		var alpha := CompassMath.fade(distance, float(config.get("fade_near_m", 12.0)), float(config.get("fade_band_m", 8.0)))
		if alpha <= 0.0:
			continue
		var placed := CompassMath.place(CompassMath.bearing(origin, at), _heading, span)
		out.append({"kind": f["kind"], "label": f["label"], "distance": distance, "x": placed["x"], "clamped": placed["clamped"], "alpha": alpha})
	# Partners whose names would overlap go by initials.
	var xs := PackedFloat32Array()
	for item in out:
		xs.append(float(item["x"]))
	var crowded := CompassMath.crowded(xs, float(config.get("crowd_share", 0.08)) * 2.0)
	for i in out.size():
		if crowded[i] and out[i]["kind"] == "partner":
			out[i]["label"] = CompassMath.initials(str(out[i]["label"]))
	return out


func _strip_rect() -> Rect2:
	var size := _canvas.size
	var w := size.x * float(config.get("width_share", 0.4))
	return Rect2((size.x - w) * 0.5, float(config.get("top_margin", 14.0)), w, float(config.get("height", 30.0)))


func _draw() -> void:
	var r := _strip_rect()
	_canvas.draw_style_box(_plate, r)
	var font := _canvas.get_theme_default_font()
	var span := float(config.get("span_degrees", 180.0))
	var step := float(config.get("tick_degrees", 15.0))
	var mid_x := r.position.x + r.size.x * 0.5
	var half := r.size.x * 0.5
	var amber := UiPalette.ACCENT
	# Every tick within the span, from the leftmost multiple of `step` rightwards.
	var first := ceilf((_heading - span * 0.5) / step) * step
	var b := first
	while b <= _heading + span * 0.5 + 0.001:
		var x := mid_x + float(CompassMath.place(fposmod(b, 360.0), _heading, span)["x"]) * half
		var deg := roundi(fposmod(b, 360.0)) % 360
		if LETTERS.has(deg):
			var letter: String = LETTERS[deg]
			var size := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, UiPalette.HUD)
			_canvas.draw_string(font, Vector2(x - size.x * 0.5, r.position.y + r.size.y * 0.5 + size.y * 0.32), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, UiPalette.HUD, amber)
		else:
			var tall := 0.42 if deg % 45 == 0 else 0.26
			_canvas.draw_line(Vector2(x, r.end.y - 3.0), Vector2(x, r.end.y - 3.0 - r.size.y * tall), Color(amber, 0.8), 2.0)
		b += step
	# Where the camera points.
	_canvas.draw_colored_polygon(PackedVector2Array([Vector2(mid_x - 6, r.position.y - 1), Vector2(mid_x + 6, r.position.y - 1), Vector2(mid_x, r.position.y + 7)]), amber)
	var colours: Dictionary = config.get("colours", {})
	var s := float(config.get("marker_size", 9.0))
	# Markers hang just under the band, clear of the letters, spread so none covers another
	# (several stuck to one end line up inward from it); left to right, so labels can take the
	# first row with room.
	var wanted: Array[float] = []
	for item in _items:
		wanted.append(mid_x + float(item["x"]) * (half - s))
	var xs := CompassMath.spread(wanted, s * 2.0 + 6.0, r.position.x + s, r.end.x - s)
	var order := range(_items.size())
	order.sort_custom(func(a: int, b2: int) -> bool: return xs[a] < xs[b2])
	var arrows := {}
	var row_end: Array[float] = [-INF, -INF]
	var line_height := font.get_height(UiPalette.BODY)
	for i: int in order:
		var item := _items[i]
		var colour := Color(str(colours.get(item["kind"], "ece6d6")))
		colour.a *= float(item["alpha"])
		var at := Vector2(xs[i], r.end.y + s + 4.0)
		_glyph(str(item["kind"]), at, s, colour)
		var dir := signf(float(item["x"]))
		if bool(item["clamped"]) and not arrows.has(dir):
			arrows[dir] = true
			var tip := Vector2((r.end.x + 4.0 + s) if dir > 0.0 else (r.position.x - 4.0 - s), r.position.y + r.size.y * 0.5)
			_canvas.draw_colored_polygon(PackedVector2Array([tip, tip - Vector2(dir * s, -s * 0.7), tip - Vector2(dir * s, s * 0.7)]), Color(UiPalette.ACCENT, 0.9))
		var text := "%d m" % roundi(float(item["distance"]))
		if not str(item["label"]).is_empty():
			text = "%s %s" % [item["label"], text]
		var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiPalette.BODY)
		var tx := clampf(at.x - size.x * 0.5, r.position.x, r.end.x - size.x)
		var row := 0 if tx > row_end[0] + 6.0 else 1
		row_end[row] = maxf(row_end[row], tx + size.x)
		var ty := at.y + s + 2.0 + line_height * (0.8 + row)
		_canvas.draw_string_outline(font, Vector2(tx, ty), text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiPalette.BODY, 4, Color(UiPalette.SHADOW, colour.a))
		_canvas.draw_string(font, Vector2(tx, ty), text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiPalette.BODY, Color(UiPalette.TEXT, colour.a))


## A shape per kind, so markers are told apart without colour too: a diamond for the
## objective, a square for a car, a house for the base, a dot for a partner.
func _glyph(kind: String, at: Vector2, s: float, colour: Color) -> void:
	var outline := Color(UiPalette.INK, colour.a)
	var points: PackedVector2Array
	match kind:
		"objective":
			points = PackedVector2Array([at + Vector2(0, -s), at + Vector2(s, 0), at + Vector2(0, s), at + Vector2(-s, 0)])
		"car":
			points = PackedVector2Array([at + Vector2(-s, -s * 0.7), at + Vector2(s, -s * 0.7), at + Vector2(s, s * 0.7), at + Vector2(-s, s * 0.7)])
		"base":
			points = PackedVector2Array([at + Vector2(0, -s), at + Vector2(s, -s * 0.15), at + Vector2(s * 0.75, s), at + Vector2(-s * 0.75, s), at + Vector2(-s, -s * 0.15)])
		_:
			_canvas.draw_circle(at, s + 1.5, outline)
			_canvas.draw_circle(at, s, colour)
			return
	var ring := PackedVector2Array(points)
	ring.append(points[0])
	_canvas.draw_colored_polygon(points, colour)
	_canvas.draw_polyline(ring, outline, 2.0)
