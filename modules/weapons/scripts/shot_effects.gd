class_name ShotEffects
extends Node
## Client-only: what every shot looks like, for every shooter. The rifle in the shooter's
## hands is the only rifle, so the flash, the tracer and the gun's kick all come from its
## muzzle. Where the bullet lands was decided by the server along the shooter's aim.

## Matches the rifle's 600 rpm interval, so sustained fire always shows a tracer.
const TRACER_SECONDS := 0.1
const IMPACT_SECONDS := 0.25
const CONFIG := "res://modules/weapons/data/weapons.json"

## Held rifle's instance id -> [rifle, where it rests in the hands], so kicks always return to
## the same place. Keyed by id, not by the node: a rifle freed with a dead soldier's body is no
## longer a Node3D, and a node-typed dictionary then refuses to erase it, every frame.
var _rest: Dictionary[int, Array] = {}
var _kick_back := 0.0
var _kick_return := 0.0


func _ready() -> void:
	var data: Variant = Data.load_json(CONFIG)
	if data is Dictionary and (data as Dictionary).has("rifle"):
		_kick_back = float(data["rifle"].get("kick_back", 0.0))
		_kick_return = float(data["rifle"].get("kick_return", 0.0))
	EventBus.subscribe(&"weapon.fired", _on_fired)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"weapon.fired", _on_fired)


func _process(delta: float) -> void:
	var prof := Prof.start()
	_process_tick(delta)
	Prof.stop(&"weapons/shot_effects:frame", prof)


func _process_tick(delta: float) -> void:
	var settle := 1.0 - exp(-_kick_return * delta)
	for id: int in _rest.keys():
		var held: Variant = _rest[id][0]
		if not is_instance_valid(held):
			_rest.erase(id)
			continue
		(held as Node3D).position = (held as Node3D).position.lerp(_rest[id][1], settle)


## Remembers where a rifle rests before its first kick.
func remember(held: Node3D) -> void:
	if not _rest.has(held.get_instance_id()):
		_rest[held.get_instance_id()] = [held, held.position]


## How many rifles are settling back after a kick.
func kicked_count() -> int:
	return _rest.size()


func _on_fired(p: Dictionary) -> void:
	var holder := p.get("holder") as Node
	var held := held_rifle(holder)
	var to: Vector3 = p["to"]
	var from: Vector3 = p["from"]
	if held != null:
		var muzzle := held.find_child("Muzzle", true, false) as Node3D
		if muzzle != null:
			from = muzzle.global_position
		remember(held)
		# The rifle's nose points along -Z, so the kick pushes it back toward the shoulder.
		held.position.z += _kick_back
	_spawn_tracer(from, to)
	_spawn_muzzle_flash(from)
	_spawn_impact(to)


## The rifle in a player's hands, or null (no body, or nothing held).
static func held_rifle(holder: Node) -> Node3D:
	if holder == null or not is_instance_valid(holder):
		return null
	var socket := PlayerBody.weapon_socket(holder)
	return socket.get_node_or_null("HeldRifle") as Node3D if socket != null else null


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


func _spawn_muzzle_flash(at: Vector3) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.45)
	light.light_energy = 2.0
	light.omni_range = 4.0
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
