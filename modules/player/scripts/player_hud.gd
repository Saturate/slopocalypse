class_name PlayerHud
extends CanvasLayer
## Client only, local player: a health bar, a red flash when hit, and the death screen with
## the respawn countdown. Reads the replicated health; never changes it.

const BAR_SIZE := Vector2(260, 14)
const FLASH_SECONDS := 0.35
const HEALTHY := Color(0.82, 0.86, 0.8)
const HURT := Color(0.9, 0.35, 0.28)

var player: PlayerController

var _health: HealthComponent
var _canvas: Control
var _last := -1.0
var _flash := 0.0
var _dead_for := -1.0
var _respawn_seconds := 5.0


func _ready() -> void:
	layer = 3
	_health = player.get_node_or_null("Health") as HealthComponent
	_respawn_seconds = float(player.config.get("respawn_seconds", 5.0))
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw)
	add_child(_canvas)
	EventBus.subscribe(&"player.died", _on_died)
	EventBus.subscribe(&"player.respawned", _on_respawned)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"player.died", _on_died)
	EventBus.unsubscribe(&"player.respawned", _on_respawned)


func _process(delta: float) -> void:
	if _health == null:
		return
	if _last >= 0.0 and _health.health < _last - 0.01:
		_flash = FLASH_SECONDS
	_last = _health.health
	_flash = maxf(_flash - delta, 0.0)
	if _dead_for >= 0.0:
		_dead_for += delta
	_canvas.queue_redraw()


func _on_died(p: Dictionary) -> void:
	if p.get("player") == player:
		_dead_for = 0.0


func _on_respawned(p: Dictionary) -> void:
	if p.get("player") == player:
		_dead_for = -1.0
		_last = -1.0


func _draw() -> void:
	var size := _canvas.size
	if _flash > 0.0:
		var a := _flash / FLASH_SECONDS * 0.25
		# A red edge, strongest at the borders, the way a hit feels.
		for i in 6:
			var w := 18.0 + i * 14.0
			var c := Color(0.75, 0.05, 0.03, a * (1.0 - i / 6.0))
			_canvas.draw_rect(Rect2(0, 0, size.x, w), c)
			_canvas.draw_rect(Rect2(0, size.y - w, size.x, w), c)
			_canvas.draw_rect(Rect2(0, 0, w, size.y), c)
			_canvas.draw_rect(Rect2(size.x - w, 0, w, size.y), c)
	var font := ThemeDB.fallback_font
	if _dead_for >= 0.0:
		_canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.0, 0.0, minf(0.65, _dead_for * 1.5)))
		var left := maxi(0, ceili(_respawn_seconds - _dead_for))
		_canvas.draw_string(font, Vector2(0, size.y / 2.0 - 10), "YOU DIED", HORIZONTAL_ALIGNMENT_CENTER, size.x, 46, Color(0.9, 0.3, 0.25))
		_canvas.draw_string(font, Vector2(0, size.y / 2.0 + 30), "Your backpack is where you fell.  Back in %d" % left, HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, Color(0.85, 0.85, 0.8))
		return
	if _health == null:
		return
	var share := clampf(_health.health / maxf(_health.max_health, 1.0), 0.0, 1.0)
	var at := Vector2(32, size.y - 48)
	_canvas.draw_rect(Rect2(at - Vector2(2, 2), BAR_SIZE + Vector2(4, 4)), Color(0, 0, 0, 0.5))
	_canvas.draw_rect(Rect2(at, Vector2(BAR_SIZE.x * share, BAR_SIZE.y)), HURT.lerp(HEALTHY, share))
	_canvas.draw_string(font, at + Vector2(0, -6), "%d" % ceili(_health.health), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.9, 0.9, 0.86))
