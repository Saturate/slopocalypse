class_name ShotFeedback
extends CanvasLayer
## Client-only: crosshair, hit marker, ammo counter, tracers and impact puffs for the
## local shooter. Reacts to `weapon.fired`; never changes game state.

## Matches the rifle's 600 rpm interval, so sustained fire always shows a tracer.
const TRACER_SECONDS := 0.1
const IMPACT_SECONDS := 0.25
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
	var muzzle: Node3D = _weapon.get_node_or_null("Model/Muzzle")
	var from: Vector3 = muzzle.global_position if muzzle != null else p["from"]
	_spawn_tracer(from, p["to"])
	_spawn_impact(p["to"])


func _draw_hud() -> void:
	var c := _hud.size / 2.0
	var white := Color(1, 1, 1, 0.95)
	var shadow := Color(0, 0, 0, 0.6)
	for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		# Dark underlay keeps the crosshair readable against bright sky.
		_hud.draw_line(c + d * 4.0, c + d * 12.0, shadow, 4.0)
		_hud.draw_line(c + d * 4.0, c + d * 12.0, white, 2.0)
	if _hit_timer > 0.0:
		var red := Color(1, 0.25, 0.2, _hit_timer / HIT_MARKER_SECONDS)
		for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			_hud.draw_line(c + d * 7.0, c + d * 15.0, red, 2.5)


## A thin glowing box along the shot; GPU line primitives are one pixel wide and vanish.
func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.01:
		return
	var box := BoxMesh.new()
	box.size = Vector3(0.012, 0.012, length)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.5)
	box.material = mat
	var tracer := MeshInstance3D.new()
	tracer.mesh = box
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world_root().add_child(tracer)
	tracer.global_transform = Transform3D(Basis.looking_at(to - from), from.lerp(to, 0.5))
	get_tree().create_timer(TRACER_SECONDS).timeout.connect(tracer.queue_free)
	_spawn_muzzle_flash(from)


func _spawn_muzzle_flash(at: Vector3) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.45)
	light.light_energy = 2.0
	light.omni_range = 4.0
	# Light the world around the muzzle, not the gun it is touching.
	light.light_cull_mask = ~ViewModel.LAYER
	_world_root().add_child(light)
	light.global_position = at
	get_tree().create_timer(TRACER_SECONDS).timeout.connect(light.queue_free)


func _spawn_impact(at: Vector3) -> void:
	var puff := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.12
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.75, 0.65)
	sphere.material = mat
	puff.mesh = sphere
	puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world_root().add_child(puff)
	puff.global_position = at
	var tween := puff.create_tween()
	tween.tween_property(puff, "scale", Vector3.ONE * 2.5, IMPACT_SECONDS)
	tween.tween_callback(puff.queue_free)


func _world_root() -> Node:
	return get_tree().current_scene if get_tree().current_scene != null else get_tree().root
