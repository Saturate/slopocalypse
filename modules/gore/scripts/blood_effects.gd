class_name BloodEffects
extends Node
## Client-only blood (#385). A shot into a player, soldier or civilian (`weapon.fired` with a
## `target` in one of the bleeding groups) throws a spray of drops out of the far side, more
## through the head, and the shot line carried on up to `splatter_reach` metres past the body
## leaves a mark on the first wall or ground it meets. A ragdoll that has settled gets a pool
## spreading under its chest. The server decides hits as before; nothing here is synced, so
## each client rolls its own drops.
##
## The player's "Blood" setting (`Settings`) is read as blood shows: off, none of it happens.

const CONFIG := "res://modules/gore/data/gore.json"
const REQUIRED := {
	"colour": TYPE_ARRAY, "spray_count": TYPE_FLOAT, "headshot_spray_count": TYPE_FLOAT, "spray_exit_depth": TYPE_FLOAT,
	"spray_speed": TYPE_FLOAT, "spray_speed_jitter": TYPE_FLOAT, "spray_angle_jitter_degrees": TYPE_FLOAT, "drop_size": TYPE_FLOAT,
	"drop_seconds": TYPE_FLOAT, "max_drops": TYPE_FLOAT, "splatter_reach": TYPE_FLOAT, "mark_size": TYPE_FLOAT,
	"mark_size_jitter": TYPE_FLOAT, "mark_stretch_max": TYPE_FLOAT, "mark_depth": TYPE_FLOAT, "pool_radius": TYPE_FLOAT,
	"pool_start_share": TYPE_FLOAT, "pool_seconds": TYPE_FLOAT, "mark_seconds": TYPE_FLOAT, "fade_seconds": TYPE_FLOAT,
	"max_marks": TYPE_FLOAT,
}
## Who bleeds: players, soldiers and civilians. Drones and towers take hits too, but are machines.
const BLEEDS: Array[StringName] = [&"players", &"enemies", &"civilians"]
## Meta on a corpse once it has been given its pool (or passed over with blood off).
const POOLED := &"gore_pooled"
## Meta on a body whose meshes have been moved off the layer marks paint.
const KEPT_CLEAN := &"gore_kept_clean"
## Seconds between looks for newly settled ragdolls: a pool starting a moment late is not seen,
## and a look walks every corpse.
const CORPSE_CHECK_SECONDS := 0.25
## How far below its chest the ground under a ragdoll is looked for, and from how far above.
const POOL_DOWN := 2.0
const POOL_UP := 0.5
## Bones a pool spreads under, the first the body has.
const POOL_BONES: Array[String] = ["Chest", "Spine", "Hips"]
## Drops catch a little light, so they read as wet rather than as red plastic.
const WET_ROUGHNESS := 0.4

static var _config: Dictionary = {}
static var _material: StandardMaterial3D

var spray: BloodSpray
var marks: BloodMarks

var _since_check := 0.0
var _warmed := false
var _rng := RandomNumberGenerator.new()


static func config() -> Dictionary:
	if _config.is_empty():
		var data: Variant = Data.load_json(CONFIG)
		if data is Dictionary and Data.require(CONFIG, data, REQUIRED):
			_config = data
	return _config


static func colour(cfg: Dictionary) -> Color:
	var c: Array = cfg["colour"]
	return Color(float(c[0]), float(c[1]), float(c[2]), float(c[3]) if c.size() > 3 else 1.0)


## The drops' material, made once: every spray shares it, so no shader is built mid-fight.
static func material(cfg: Dictionary) -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		var c := colour(cfg)
		_material.albedo_color = Color(c.r, c.g, c.b)
		_material.roughness = WET_ROUGHNESS
	return _material


static func blood_on() -> bool:
	return bool(Settings.value("blood"))


## How big a mark is on a surface facing `normal` hit along `direction`: `size` across, and
## longer along the shot the more it grazes the surface, up to `mark_stretch_max` times.
## Returns (width, length).
static func mark_shape(direction: Vector3, normal: Vector3, size: float, cfg: Dictionary) -> Vector2:
	var facing := absf(direction.normalized().dot(normal.normalized()))
	var stretch := clampf(1.0 / maxf(facing, 0.001), 1.0, float(cfg["mark_stretch_max"]))
	return Vector2(size, size * stretch)


func _ready() -> void:
	var cfg := config()
	if cfg.is_empty():
		return
	_rng.randomize()
	spray = BloodSpray.new()
	spray.setup(cfg)
	add_child(spray)
	marks = BloodMarks.new()
	marks.setup(cfg)
	add_child(marks)
	EventBus.subscribe(&"weapon.fired", on_fired)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"weapon.fired", on_fired)


func _process(delta: float) -> void:
	var prof := Prof.start()
	_process_tick(delta)
	Prof.stop(&"gore/effects:frame", prof)


func _process_tick(delta: float) -> void:
	if marks == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		marks.keep_warm(camera)
		if not _warmed:
			_warmed = true
			spray.warm(camera.global_position - camera.global_basis.z * BloodMarks.KEEPER_AHEAD)
	_since_check += delta
	if _since_check < CORPSE_CHECK_SECONDS:
		return
	_since_check = 0.0
	check_corpses()


func on_fired(p: Dictionary) -> void:
	if spray == null or not blood_on():
		return
	var target: Variant = p.get("target")
	if not is_instance_valid(target) or not target is Node3D or not _bleeds(target as Node):
		return
	var from: Vector3 = p.get("from", Vector3.ZERO)
	var to: Vector3 = p.get("to", Vector3.ZERO)
	var direction := (to - from).normalized()
	if direction.is_zero_approx():
		return
	var cfg := config()
	var exit := to + direction * float(cfg["spray_exit_depth"])
	var headshot := HitscanWeapon.is_headshot(target as Node, to)
	spray.spray(exit, direction, int(cfg["headshot_spray_count" if headshot else "spray_count"]))
	if not target.has_meta(KEPT_CLEAN):
		target.set_meta(KEPT_CLEAN, true)
		keep_blood_off(target as Node)
	_mark_behind(exit, direction, target as Node3D)


## Gives every ragdoll that has settled since the last look its pool.
func check_corpses() -> void:
	if marks == null:
		return
	for node in get_tree().get_nodes_in_group(Corpse.GROUP):
		var corpse := node as Corpse
		if corpse == null or corpse.has_meta(POOLED) or not corpse.is_settled():
			continue
		corpse.set_meta(POOLED, true)
		if blood_on():
			_pool_under(corpse)


func _bleeds(node: Node) -> bool:
	for group in BLEEDS:
		if node.is_in_group(group):
			return true
	return false


## The shot line carried on past the body: a mark on the first surface it meets in reach.
func _mark_behind(exit: Vector3, direction: Vector3, target: Node3D) -> void:
	var cfg := config()
	var exclude: Array[RID] = []
	if target is CollisionObject3D:
		exclude.append((target as CollisionObject3D).get_rid())
	var query := PhysicsRayQueryParameters3D.create(exit, exit + direction * float(cfg["splatter_reach"]), PhysicsLayers.BULLETS, exclude)
	var hit := marks.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	# Another body behind the first: the spray is enough, a decal would paint the person.
	if hit["collider"] is Node and _bleeds(hit["collider"] as Node):
		return
	var size := float(cfg["mark_size"]) * (1.0 + _rng.randf_range(-1.0, 1.0) * float(cfg["mark_size_jitter"]))
	var shape := mark_shape(direction, hit["normal"], size, cfg)
	marks.add_mark(hit["position"], hit["normal"], direction, shape.x, shape.y)


func _pool_under(corpse: Corpse) -> void:
	var skeleton := corpse.skeleton
	var bone := -1
	for bone_name in POOL_BONES:
		bone = skeleton.find_bone(bone_name)
		if bone >= 0:
			break
	if bone < 0:
		return
	var chest := (skeleton.global_transform * skeleton.get_bone_global_pose(bone)).origin
	var query := PhysicsRayQueryParameters3D.create(chest + Vector3.UP * POOL_UP, chest + Vector3.DOWN * POOL_DOWN, PhysicsLayers.BULLETS)
	var hit := corpse.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	keep_blood_off(corpse)
	marks.add_pool(hit["position"], hit["normal"], float(config()["pool_radius"]))


## Moves `node`'s meshes onto the render layer marks and pools leave alone: a corpse lies in
## its pool instead of being painted by it, and someone standing against a wall that is
## splattered behind them stays clean. Nothing else draws by layer, and cameras see them all.
static func keep_blood_off(node: Node) -> void:
	for child in node.find_children("*", "VisualInstance3D", true, false):
		(child as VisualInstance3D).layers = BloodMarks.NO_DECALS
