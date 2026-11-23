class_name ShotFeedback
extends CanvasLayer
## Client-only HUD for the local shooter: crosshair, hit marker, where hits on you came
## from, and ammo (magazine over its size, a reload bar, amber when running low). Tracers
## and flashes are ShotEffects, for everyone's shots. Never changes game state.
##
## Minimal: no panels. Ammo fades back when the magazine is full and you haven't fired for
## a while. All of it hides while you are dead.

const HIT_MARKER_SECONDS := 0.18
const DAMAGE_ARC_SECONDS := 1.6
## Half the width of a damage arc, in radians.
const DAMAGE_ARC_HALF := 0.35
const DAMAGE_ARC_RADIUS := 150.0
## Magazine at or below this share shows in the warning colour.
const LOW_AMMO_SHARE := 0.3
const QUIET_SECONDS := 4.0
const FADED_ALPHA := 0.5
const FADE_RATE := 3.0
const MARGIN := Vector2(36, 40)

var local_player: PlayerController

var _hud := Control.new()
var _magazine := Label.new()
var _size := Label.new()
var _name := Label.new()
var _hit_timer := 0.0
## Starts at zero so the readout shows when you spawn, then fades.
var _since_fired := 0.0
var _reload_for := -1.0
var _alpha := 1.0
var _dead := false
## {angle: radians from straight ahead, clockwise; left: seconds}
var _arcs: Array[Dictionary] = []
var _weapon: HitscanWeapon


func _ready() -> void:
	layer = UiLayers.HUD
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.draw.connect(_draw_hud)
	add_child(_hud)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	column.grow_vertical = Control.GROW_DIRECTION_BEGIN
	column.offset_right = -MARGIN.x
	column.offset_bottom = -MARGIN.y + 10
	column.add_theme_constant_override(&"separation", -8)
	_hud.add_child(column)
	_name.theme_type_variation = &"HudLabel"
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(_name)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override(&"separation", 6)
	column.add_child(row)
	_magazine.theme_type_variation = &"HudNumber"
	row.add_child(_magazine)
	_size.theme_type_variation = &"HudLabel"
	_size.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(_size)
	for l: Label in [_name, _magazine, _size]:
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	EventBus.subscribe(&"weapon.fired", _on_fired)
	EventBus.subscribe(&"player.died", _on_died)
	EventBus.subscribe(&"player.respawned", _on_respawned)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"weapon.fired", _on_fired)
	EventBus.unsubscribe(&"player.died", _on_died)
	EventBus.unsubscribe(&"player.respawned", _on_respawned)


func _process(delta: float) -> void:
	var prof := Prof.start()
	_process_tick(delta)
	Prof.stop(&"weapons/shot_feedback:frame", prof)


func _process_tick(delta: float) -> void:
	_hit_timer = maxf(_hit_timer - delta, 0.0)
	_since_fired += delta
	for i in range(_arcs.size() - 1, -1, -1):
		_arcs[i]["left"] = float(_arcs[i]["left"]) - delta
		if float(_arcs[i]["left"]) <= 0.0:
			_arcs.remove_at(i)
	# Follow the drawn gun: a swap replaces it, switching changes it.
	_weapon = _carried()
	_hud.visible = not _dead
	var full := true
	if _weapon != null:
		var size := magazine_size()
		var left := _weapon.ammo()
		full = left >= size and not _weapon.is_reloading()
		_reload_for = (_reload_for + delta if _reload_for >= 0.0 else 0.0) if _weapon.is_reloading() else -1.0
		_magazine.text = "%02d" % left
		_size.text = "/ %d" % size
		_name.text = _weapon.weapon_id.capitalize()
		_magazine.add_theme_color_override(&"font_color", UiPalette.WARN if is_low() else UiPalette.TEXT)
	for l: Label in [_name, _magazine, _size]:
		l.visible = _weapon != null
	var target := 1.0 if not full or _since_fired < QUIET_SECONDS else FADED_ALPHA
	_alpha = lerpf(_alpha, target, 1.0 - exp(-FADE_RATE * delta))
	for l: Label in [_name, _magazine, _size]:
		l.modulate.a = _alpha
	_hud.queue_redraw()


func magazine_size() -> int:
	if _weapon == null:
		return 0
	return int(_weapon.stats.get("magazine", 0))


func is_low() -> bool:
	var size := magazine_size()
	return _weapon != null and size > 0 and float(_weapon.ammo()) <= float(size) * LOW_AMMO_SHARE


## Damage arcs showing now, for tests.
func arcs() -> Array[Dictionary]:
	return _arcs


func _carried() -> HitscanWeapon:
	if local_player == null:
		return null
	for child in local_player.get_node("Head/Camera").get_children():
		if child is HitscanWeapon and (child as HitscanWeapon).active and not child.is_queued_for_deletion():
			return child
	return null


func _on_fired(p: Dictionary) -> void:
	if local_player == null:
		return
	if p.get("holder") == local_player:
		_weapon = p["weapon"]
		_since_fired = 0.0
		if float(p["damage"]) > 0.0:
			_hit_timer = HIT_MARKER_SECONDS
	elif p.get("target") == local_player and float(p.get("damage", 0.0)) > 0.0:
		_arcs.append({"angle": angle_to(p.get("from", local_player.global_position)), "left": DAMAGE_ARC_SECONDS})


## Where `from` is around the player, in radians clockwise from straight ahead.
func angle_to(from: Vector3) -> float:
	var local := local_player.global_basis.inverse() * (from - local_player.global_position)
	return atan2(local.x, -local.z)


func _on_died(p: Dictionary) -> void:
	if p.get("player") == local_player:
		_dead = true
		_arcs.clear()


func _on_respawned(p: Dictionary) -> void:
	if p.get("player") == local_player:
		_dead = false


func _draw_hud() -> void:
	var c := _hud.size / 2.0
	for arc: Dictionary in _arcs:
		var a := -PI / 2.0 + float(arc["angle"])
		var fade := float(arc["left"]) / DAMAGE_ARC_SECONDS
		_hud.draw_arc(c, DAMAGE_ARC_RADIUS, a - DAMAGE_ARC_HALF, a + DAMAGE_ARC_HALF, 24, Color(0, 0, 0, 0.5 * fade), 16.0)
		_hud.draw_arc(c, DAMAGE_ARC_RADIUS, a - DAMAGE_ARC_HALF, a + DAMAGE_ARC_HALF, 24, Color(UiPalette.BAD, fade), 10.0)
	if _reload_for >= 0.0 and _weapon != null:
		var share := clampf(_reload_for / maxf(float(_weapon.stats.get("reload_seconds", 1.0)), 0.01), 0.0, 1.0)
		var bar := Rect2(c + Vector2(-40, 34), Vector2(80, 4))
		_hud.draw_rect(Rect2(bar.position + Vector2(0, 1), bar.size), Color(0, 0, 0, 0.5))
		_hud.draw_rect(bar, Color(1, 1, 1, 0.2))
		_hud.draw_rect(Rect2(bar.position, Vector2(bar.size.x * share, bar.size.y)), UiPalette.ACCENT)
	# Looking through the sight, the sight is the crosshair.
	var aiming := local_player != null and local_player.intent().aim
	var white := Color(1, 1, 1, 0.95)
	var shadow := Color(0, 0, 0, 0.6)
	# No crosshair on a ladder either: the gun is down and can't fire there.
	if not aiming and not (local_player != null and local_player.climbing):
		for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			# Dark underlay keeps the crosshair readable against bright sky.
			_hud.draw_line(c + d * 5.0, c + d * 12.0, shadow, 4.0)
			_hud.draw_line(c + d * 5.0, c + d * 12.0, white, 2.0)
	if _hit_timer > 0.0:
		var a := _hit_timer / HIT_MARKER_SECONDS
		for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var n := d.normalized()
			_hud.draw_line(c + n * 12.0, c + n * 24.0, Color(0, 0, 0, 0.6 * a), 6.0)
			_hud.draw_line(c + n * 12.0, c + n * 24.0, Color(1, 1, 1, a), 3.0)
