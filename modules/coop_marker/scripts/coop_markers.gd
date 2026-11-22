class_name CoopMarkers
extends CanvasLayer
## Client only, local player (#447): a small blue marker over each other co-op player with
## their name and distance, drawn through walls. How strongly it shows comes from
## CoopMarkerRules; this finds the partners, checks the line of sight and draws. Off in
## Settings ("coop_marker").

var config: Dictionary = {}
## The local player; nothing is drawn without one, or while they are dead.
var player: Node3D
## Player instance id -> the car (Node3D) they sit in, kept by the module from `car.entered`
## and `car.exited`. Shared, not copied, so seats taken before this layer existed count.
var rides: Dictionary = {}

var _canvas: Control
var _items: Array[Dictionary] = []
## Shown alpha per partner (instance id), eased towards the rules' target.
var _shown: Dictionary = {}
var _colour := Color.WHITE


func _ready() -> void:
	layer = UiLayers.HUD
	_colour = Color(str(config["colour"]))
	_canvas = Control.new()
	_canvas.name = "Canvas"
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw)
	add_child(_canvas)


func _process(delta: float) -> void:
	var prof := Prof.start()
	visible = bool(Settings.value("coop_marker"))
	var found: Array[Dictionary] = []
	if visible:
		found = items()
	if found.is_empty() and _items.is_empty():
		_shown.clear()
		Prof.stop(&"coop_marker/markers:frame", prof)
		return
	var rate := float(config["fade_rate"])
	var seen := {}
	for item in found:
		var id: int = item["id"]
		seen[id] = true
		var shown := CoopMarkerRules.ease_alpha(float(_shown.get(id, 0.0)), float(item["alpha"]), rate, delta)
		_shown[id] = shown
		item["shown"] = shown
	for id: int in _shown.keys():
		if not seen.has(id):
			_shown.erase(id)
	_items = found
	_canvas.queue_redraw()
	Prof.stop(&"coop_marker/markers:frame", prof)


## A marker per partner now: {id, name, distance, metres, in_sight, alpha (the rules' target),
## ahead (in front of the camera), at (screen position of the marker's tip)}. Empty without a
## camera or a living local player.
func items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var camera := get_viewport().get_camera_3d()
	if camera == null or player == null or not is_instance_valid(player) or bool(player.get_meta(&"dead", false)):
		return out
	var eye := camera.global_position
	var space := camera.get_world_3d().direct_space_state
	var my_car := _ride_of(player)
	for other: Node in get_tree().get_nodes_in_group(&"players"):
		var car := _ride_of(other)
		if not CoopMarkerRules.is_partner(other, player, car != null):
			continue
		var body := other as Node3D
		var anchor := car if car != null else body
		var distance := eye.distance_to(anchor.global_position)
		if distance > float(config["range_m"]):
			continue
		var in_sight := _in_sight(space, eye, anchor, [player, body, my_car, car])
		var top := anchor.global_position + Vector3.UP * float(config["marker_height_m"])
		var ahead := not camera.is_position_behind(top)
		out.append({
			"id": body.get_instance_id(),
			"name": str(body.get_meta(&"player_name", "")),
			"distance": distance,
			"metres": CoopMarkerRules.metres(distance),
			"in_sight": in_sight,
			"alpha": CoopMarkerRules.alpha(distance, in_sight, config),
			"ahead": ahead,
			"at": camera.unproject_position(top) if ahead else Vector2.ZERO,
		})
	return out


func _ride_of(who: Node) -> Node3D:
	var car: Variant = rides.get(who.get_instance_id())
	return car as Node3D if is_instance_valid(car) and car is Node3D else null


## Nothing that blocks eyes between `eye` and the partner's chest. `skip`: the two players
## and any car either sits in, which would otherwise always stand in the way of the ray.
func _in_sight(space: PhysicsDirectSpaceState3D, eye: Vector3, anchor: Node3D, skip: Array) -> bool:
	if space == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(eye, anchor.global_position + Vector3.UP * float(config["aim_height_m"]), PhysicsLayers.SOLID | PhysicsLayers.SIGHT)
	var exclude: Array[RID] = []
	for n: Variant in skip:
		if n is CollisionObject3D:
			exclude.append((n as CollisionObject3D).get_rid())
	query.exclude = exclude
	return space.intersect_ray(query).is_empty()


func _draw() -> void:
	var font := _canvas.get_theme_default_font()
	var s := float(config["marker_size"])
	var name_size := int(config["name_size"])
	var distance_size := int(config["distance_size"])
	var bounds := Rect2(Vector2.ZERO, _canvas.size)
	for item in _items:
		var a := float(item.get("shown", 0.0))
		if a <= 0.01 or not bool(item["ahead"]):
			continue
		var tip: Vector2 = item["at"]
		# Room for the label, so a head just past the edge still shows its name.
		if not bounds.grow(s * 4.0).has_point(tip):
			continue
		var ink := Color(UiPalette.INK, a * 0.9)
		var colour := Color(_colour, _colour.a * a)
		var chevron := PackedVector2Array([tip, tip + Vector2(-s, -s * 1.2), tip + Vector2(s, -s * 1.2)])
		var ring := PackedVector2Array(chevron)
		ring.append(chevron[0])
		_canvas.draw_colored_polygon(chevron, colour)
		_canvas.draw_polyline(ring, ink, 2.0)
		var y := tip.y - s * 1.2 - 4.0
		y = _text(font, "%d m" % int(item["metres"]), tip.x, y, distance_size, colour, ink)
		var who := str(item["name"])
		if not who.is_empty():
			_text(font, who, tip.x, y - 2.0, name_size, colour, ink)


## Draws `text` centred on `x` with its baseline at `baseline`; returns the top of the line.
func _text(font: Font, text: String, x: float, baseline: float, size: int, colour: Color, outline: Color) -> float:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var at := Vector2(x - width * 0.5, baseline)
	_canvas.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 5, outline)
	_canvas.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, colour)
	return baseline - font.get_ascent(size)
