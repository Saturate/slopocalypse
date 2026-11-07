class_name ShotFeedback
extends CanvasLayer
## Client-only HUD for the local shooter: crosshair, hit marker and ammo counter. Tracers
## and flashes are ShotEffects, for everyone's shots. Never changes game state.

const HIT_MARKER_SECONDS := 0.15

var local_player: PlayerController

var _hud := Control.new()
var _ammo := Label.new()
var _hit_timer := 0.0
var _weapon: HitscanWeapon


func _ready() -> void:
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.draw.connect(_draw_hud)
	add_child(_hud)
	_ammo.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_ammo.position = Vector2(-140, -60)
	_ammo.add_theme_font_size_override(&"font_size", 28)
	_hud.add_child(_ammo)
	EventBus.subscribe(&"weapon.fired", _on_fired)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"weapon.fired", _on_fired)


func _process(delta: float) -> void:
	_hit_timer = maxf(_hit_timer - delta, 0.0)
	if _weapon != null:
		_ammo.text = "RELOADING" if _weapon.rules.is_reloading() else "%d" % _weapon.ammo()
	_hud.queue_redraw()


func _on_fired(p: Dictionary) -> void:
	if p.get("holder") != local_player:
		return
	_weapon = p["weapon"]
	if float(p["damage"]) > 0.0:
		_hit_timer = HIT_MARKER_SECONDS


func _draw_hud() -> void:
	var c := _hud.size / 2.0
	# Looking through the sight, the sight is the crosshair.
	var aiming := local_player != null and local_player.intent().aim
	if aiming and _hit_timer <= 0.0:
		return
	var white := Color(1, 1, 1, 0.95)
	var shadow := Color(0, 0, 0, 0.6)
	for d: Vector2 in ([] if aiming else [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]):
		# Dark underlay keeps the crosshair readable against bright sky.
		_hud.draw_line(c + d * 4.0, c + d * 12.0, shadow, 4.0)
		_hud.draw_line(c + d * 4.0, c + d * 12.0, white, 2.0)
	if _hit_timer > 0.0:
		var red := Color(1, 0.25, 0.2, _hit_timer / HIT_MARKER_SECONDS)
		for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			_hud.draw_line(c + d * 7.0, c + d * 15.0, red, 2.5)
