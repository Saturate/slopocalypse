class_name PlayerHud
extends CanvasLayer
## Client only, local player: health (number and a thin bar, bottom left), a red flash at
## the edges when hit, a pulsing red edge while health is low, and the death screen with
## the respawn countdown. Reads the replicated health; never changes it.
##
## Minimal on purpose: no panels over the world. Health fades back when it is full and
## nothing has hurt you for a while.

const FLASH_SECONDS := 0.35
const BAR_SIZE := Vector2(200, 6)
## Below this share of health the edges pulse red, stronger the lower it gets.
const LOW_SHARE := 0.35
const PULSE_HZ := 1.1
## Full health and no hit for this long: the health readout fades to FADED_ALPHA.
const QUIET_SECONDS := 4.0
const FADED_ALPHA := 0.5
const FADE_RATE := 3.0
const MARGIN := Vector2(36, 40)

var player: PlayerController

var _health: HealthComponent
var _canvas: Control
var _number: Label
var _died: Label
var _respawn: Label
var _last := -1.0
var _flash := 0.0
## Starts at zero so the readout shows when you spawn, then fades.
var _since_hit := 0.0
var _alpha := 1.0
var _clock := 0.0
var _dead_for := -1.0
var _respawn_seconds := 5.0
var _edges: GradientTexture2D


func _ready() -> void:
	layer = UiLayers.HUD
	_health = player.get_node_or_null("Health") as HealthComponent
	_respawn_seconds = float(player.config.get("respawn_seconds", 5.0))
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw)
	add_child(_canvas)
	_number = Label.new()
	_number.theme_type_variation = &"HudNumber"
	_number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_number.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_number.grow_vertical = Control.GROW_DIRECTION_BEGIN
	# Sits on the bar.
	_number.offset_left = MARGIN.x - 2
	_number.offset_bottom = -MARGIN.y - BAR_SIZE.y + 4
	_number.offset_top = _number.offset_bottom - 52
	_canvas.add_child(_number)
	_died = _centred(&"TitleLabel", -40)
	_died.text = "YOU DIED"
	_died.add_theme_color_override(&"font_color", UiPalette.BAD)
	_died.add_theme_font_size_override(&"font_size", 64)
	_respawn = _centred(&"HudLabel", 30)
	_edges = GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.6, 0.0, 0.0, 0.0))
	g.set_color(1, Color(0.6, 0.0, 0.0, 1.0))
	g.set_offset(0, 0.55)
	_edges.gradient = g
	_edges.fill = GradientTexture2D.FILL_RADIAL
	_edges.fill_from = Vector2(0.5, 0.5)
	_edges.fill_to = Vector2(1.05, 1.05)
	EventBus.subscribe(&"player.died", _on_died)
	EventBus.subscribe(&"player.respawned", _on_respawned)


func _centred(variation: StringName, offset_y: float) -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	l.anchor_right = 1.0
	l.offset_top = offset_y - 40
	l.offset_bottom = offset_y + 40
	l.visible = false
	_canvas.add_child(l)
	return l


func _exit_tree() -> void:
	EventBus.unsubscribe(&"player.died", _on_died)
	EventBus.unsubscribe(&"player.respawned", _on_respawned)


func _process(delta: float) -> void:
	var prof := Prof.start()
	_process_tick(delta)
	Prof.stop(&"player/player_hud:frame", prof)


func _process_tick(delta: float) -> void:
	if _health == null:
		return
	_clock += delta
	if _last >= 0.0 and _health.health < _last - 0.01:
		_flash = FLASH_SECONDS
		_since_hit = 0.0
	_last = _health.health
	_flash = maxf(_flash - delta, 0.0)
	_since_hit += delta
	var share := health_share()
	var target := 1.0 if share < 1.0 or _since_hit < QUIET_SECONDS else FADED_ALPHA
	_alpha = lerpf(_alpha, target, 1.0 - exp(-FADE_RATE * delta))
	var dead := _dead_for >= 0.0
	if dead:
		_dead_for += delta
		_respawn.text = "Your backpack is where you fell.  Back in %d" % maxi(0, ceili(_respawn_seconds - _dead_for))
	_died.visible = dead
	_respawn.visible = dead
	_number.visible = not dead
	_number.text = "%d" % ceili(_health.health)
	_number.add_theme_color_override(&"font_color", UiPalette.BAD if share < LOW_SHARE else UiPalette.TEXT)
	_number.modulate.a = _alpha
	_canvas.queue_redraw()


## Health as a share of the maximum, 0 to 1.
func health_share() -> float:
	if _health == null:
		return 0.0
	return clampf(_health.health / maxf(_health.max_health, 1.0), 0.0, 1.0)


## How strongly the edges glow red now: the hit flash plus the low-health pulse.
func edge_strength() -> float:
	var flash := _flash / FLASH_SECONDS * 0.5
	var share := health_share()
	var low := 0.0
	if share < LOW_SHARE and _dead_for < 0.0:
		var depth := (LOW_SHARE - share) / LOW_SHARE
		low = 0.25 + depth * 0.35 + 0.15 * sin(_clock * TAU * PULSE_HZ)
	return clampf(maxf(flash, low), 0.0, 1.0)


## Past halfway from shown to faded.
func is_faded() -> bool:
	return _alpha < (1.0 + FADED_ALPHA) / 2.0


func _on_died(p: Dictionary) -> void:
	if p.get("player") == player:
		_dead_for = 0.0


func _on_respawned(p: Dictionary) -> void:
	if p.get("player") == player:
		_dead_for = -1.0
		_last = -1.0


func _draw() -> void:
	var size := _canvas.size
	var edges := edge_strength()
	if edges > 0.0:
		_canvas.draw_texture_rect(_edges, Rect2(Vector2.ZERO, size), false, Color(1, 1, 1, edges))
	if _dead_for >= 0.0:
		_canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.0, 0.0, minf(0.7, _dead_for * 1.5)))
		return
	if _health == null:
		return
	var share := health_share()
	var at := Vector2(MARGIN.x, size.y - MARGIN.y - BAR_SIZE.y)
	var colour := UiPalette.BAD if share < LOW_SHARE else UiPalette.TEXT
	_canvas.draw_rect(Rect2(at + Vector2(0, 2), BAR_SIZE), Color(0, 0, 0, 0.45 * _alpha))
	_canvas.draw_rect(Rect2(at, BAR_SIZE), Color(1, 1, 1, 0.15 * _alpha))
	_canvas.draw_rect(Rect2(at, Vector2(BAR_SIZE.x * share, BAR_SIZE.y)), Color(colour, _alpha))
