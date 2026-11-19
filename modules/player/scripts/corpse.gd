class_name Corpse
extends Node3D
## A dead body that falls as a ragdoll, on each client alone (#130). `from_body` copies the
## dying soldier's or player's body (same meshes and materials, so no new shaders to compile
## mid-fight), poses the copy as the body stood, gives its bones physics and a push away from
## whoever killed them. After `settle_seconds` the pose is kept and the physics goes.
##
## The searchable body is the inventory's LootBody, which the server spawns where they fell.
## A corpse and the LootBody near where it fell find each other, whichever arrives first; the
## corpse then stands in for the LootBody's figure and goes when the LootBody does. A corpse
## that finds none goes after `seconds_without_body`. The living body is left alone: players
## respawn with it, soldiers' nodes are freed soon after they die.

const CONFIG := "res://modules/player/data/ragdoll.json"
const REQUIRED := {
	"settle_seconds": TYPE_FLOAT, "min_fall_seconds": TYPE_FLOAT, "max_simulating": TYPE_FLOAT, "seconds_without_body": TYPE_FLOAT,
	"link_radius": TYPE_FLOAT, "link_seconds": TYPE_FLOAT, "push": TYPE_FLOAT, "push_up": TYPE_FLOAT, "linear_damp": TYPE_FLOAT,
	"angular_damp": TYPE_FLOAT, "friction": TYPE_FLOAT, "bones": TYPE_DICTIONARY,
}
const BONE_REQUIRED := {"size": TYPE_ARRAY, "centre": TYPE_ARRAY, "mass": TYPE_FLOAT, "swing": TYPE_FLOAT, "twist": TYPE_FLOAT}
## Parts of the living body a corpse has no use for: what animates it, aims it and holds the gun.
const STRIP: Array[String] = ["AnimationTree", "AnimationPlayer", "Skeleton/Aim", "Skeleton/HandIK", "Skeleton/WeaponAttachment"]
const GROUP := &"corpses"
## The LootBody this corpse stands in for, as meta on both.
const LINK := &"corpse_link"
## When a LootBody arrived (msec), as meta on it: a corpse only takes one that is recent.
const ARRIVED := &"corpse_arrived"

## Off on a dedicated server, which draws nothing; tests turn it on.
static var enabled := DisplayServer.get_name() != "headless"
static var _config: Dictionary = {}
## Corpses still simulating, oldest first: past `max_simulating` the oldest settles early.
static var _simulating: Array[Corpse] = []

var skeleton: Skeleton3D
var simulator: PhysicalBoneSimulator3D

## Where it fell: what a LootBody is matched against, wherever the ragdoll has rolled since.
var _fell_at := Vector3.ZERO
var _age := 0.0
var _settled := false
var _velocity := Vector3.ZERO
var _pushed := false


static func config() -> Dictionary:
	if _config.is_empty():
		var data: Variant = Data.load_json(CONFIG)
		if data is Dictionary and Data.require(CONFIG, data, REQUIRED):
			_config = data
	return _config


## A corpse falling from `player`'s body as it stands now, pushed along `push` (metres a
## second) on top of the speed it had. Null when not `enabled`, or without a body.
static func from_body(player: Node3D, push: Vector3, velocity := Vector3.ZERO) -> Corpse:
	# Hidden (sitting in a car) there is no body to fall: it would land inside the car.
	if not enabled or not player.is_inside_tree() or not player.is_visible_in_tree():
		return null
	var cfg := config()
	var body := player.get_node_or_null("Body") as Node3D
	var source := player.get_node_or_null("Body/Skeleton") as Skeleton3D
	if cfg.is_empty() or body == null or source == null:
		return null
	var copy := body.duplicate() as Node3D
	for path in STRIP:
		var part := copy.get_node_or_null(path)
		if part != null:
			part.get_parent().remove_child(part)
			part.free()
	copy.transform = Transform3D.IDENTITY
	copy.visible = true
	var corpse := Corpse.new()
	corpse.name = "Corpse"
	corpse.top_level = true
	corpse.add_child(copy)
	corpse.skeleton = copy.get_node("Skeleton") as Skeleton3D
	for mesh in corpse.skeleton.get_children():
		# Your own first-person body only casts a shadow and its arms take none; dead, it is
		# seen like anyone's.
		if mesh is GeometryInstance3D:
			var geometry := mesh as GeometryInstance3D
			if geometry.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				geometry.material_override = null
			geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_copy_pose(source, corpse.skeleton)
	corpse._add_bones(cfg)
	if player is PhysicsBody3D:
		# It starts inside the dead body's capsule, which is only switched off at the end of
		# the frame; hitting it would stop the fall where it began.
		for bone in corpse.simulator.get_children():
			(bone as PhysicalBone3D).add_collision_exception_with(player)
	corpse._velocity = velocity + push
	# Placed before it enters the tree: its physics starts in `_ready`, from where it is then.
	corpse.transform = body.global_transform
	corpse._fell_at = player.global_position
	player.get_parent().add_child(corpse)
	return corpse


## Which way a body killed by `source` falls: away from it, and a little up.
static func push_from(victim: Node3D, source: Variant) -> Vector3:
	var cfg := config()
	if cfg.is_empty():
		return Vector3.ZERO
	var away := Vector3.ZERO
	if is_instance_valid(source) and source is Node3D:
		away = victim.global_position - (source as Node3D).global_position
		away.y = 0.0
	if away.length() < 0.01:
		# No killer (a fall, a blast with no owner): over backwards.
		away = victim.global_transform.basis.z
	return away.normalized() * float(cfg["push"]) + Vector3.UP * float(cfg["push_up"])


## Links `loot` (a LootBody that just arrived) with the corpse that fell nearest it in the
## last `link_seconds`, if any. Only recent ones: a death that leaves no LootBody (a civilian
## carries nothing) must not take one from a later death nearby.
static func link_near(loot: Node3D) -> void:
	if not enabled:
		return
	loot.set_meta(ARRIVED, Time.get_ticks_msec())
	if loot.has_meta(LINK):
		return
	var cfg := config()
	var radius := float(cfg.get("link_radius", 0.0))
	var best: Corpse = null
	for node in loot.get_tree().get_nodes_in_group(GROUP):
		var corpse := node as Corpse
		var d := _flat_distance(corpse._fell_at, loot.global_position)
		if not corpse.has_meta(LINK) and corpse._age <= float(cfg.get("link_seconds", 0.0)) and d <= radius and (best == null or d < _flat_distance(best._fell_at, loot.global_position)):
			best = corpse
	if best != null:
		best._link(loot)


## Across the ground only: a LootBody lies on the ground below a death in mid-air or in deep
## water, metres under where the body was.
static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func _copy_pose(from: Skeleton3D, to: Skeleton3D) -> void:
	# Global poses are what is on screen, after the aim and hand modifiers had their say.
	for i in from.get_bone_count():
		var parent := from.get_bone_parent(i)
		var global_pose := from.get_bone_global_pose(i)
		var local := global_pose if parent < 0 else from.get_bone_global_pose(parent).affine_inverse() * global_pose
		to.set_bone_pose(i, local)


func is_settled() -> bool:
	return _settled


## The LootBody this corpse stands in for, or null.
func loot_body() -> Node3D:
	if not has_meta(LINK):
		return null
	var loot: Variant = get_meta(LINK)
	return loot as Node3D if is_instance_valid(loot) else null


func _ready() -> void:
	add_to_group(GROUP)
	# The LootBody may have got here first; later ones find this corpse themselves.
	_look_for_loot()
	simulator.physical_bones_start_simulation()
	_simulating.append(self)
	var cap := int(config()["max_simulating"])
	# Over the cap, settle the oldest that have fallen for a while; one that has barely started
	# would keep a standing pose, so the cap gives way for a moment instead.
	var fallen := float(config()["min_fall_seconds"])
	for corpse in _simulating.duplicate():
		if _simulating.size() <= cap:
			break
		if corpse != self and corpse._age >= fallen:
			corpse._settle()


func _exit_tree() -> void:
	_simulating.erase(self)
	var loot := loot_body()
	if loot != null and not loot.is_queued_for_deletion() and loot.has_method(&"show_figure"):
		loot.call(&"show_figure", true)


func _physics_process(delta: float) -> void:
	var prof := Prof.start()
	_physics_tick(delta)
	Prof.stop(&"player/corpse:physics", prof)


func _physics_tick(delta: float) -> void:
	if not _pushed and not _settled:
		_push()
	_age += delta
	var cfg := config()
	if not _settled and _age >= float(cfg["settle_seconds"]):
		_settle()
	if has_meta(LINK):
		if _settled:
			set_physics_process(false)
		return
	if _age >= float(cfg["seconds_without_body"]):
		queue_free()


func _look_for_loot() -> void:
	var cfg := config()
	var radius := float(cfg["link_radius"])
	var recent := int(float(cfg["link_seconds"]) * 1000.0)
	var best: Node3D = null
	for node in get_tree().get_nodes_in_group(&"loot_bodies"):
		var loot := node as Node3D
		if loot == null or loot.has_meta(LINK) or Time.get_ticks_msec() - int(loot.get_meta(ARRIVED, 0)) > recent:
			continue
		var d := _flat_distance(loot.global_position, _fell_at)
		if d <= radius and (best == null or d < _flat_distance(best.global_position, _fell_at)):
			best = loot
	if best != null:
		_link(best)


## The inventory's LootBody (group `loot_bodies`, `show_figure`) is matched by group and
## duck typing, so the player module needs nothing from the inventory.
func _link(loot: Node3D) -> void:
	set_meta(LINK, loot)
	loot.set_meta(LINK, self)
	if loot.has_method(&"show_figure"):
		loot.call(&"show_figure", false)
	loot.tree_exiting.connect(queue_free)


## Sets the bones moving once they really simulate: the simulator only switches them over in
## its own processing, and a bone still following the skeleton drops what it is given.
func _push() -> void:
	var bones := simulator.get_children()
	if bones.is_empty() or not (bones[0] as PhysicalBone3D).is_simulating_physics():
		return
	_pushed = true
	for bone in bones:
		(bone as PhysicalBone3D).linear_velocity = _velocity


## Keeps the pose the ragdoll fell into and drops its physics.
func _settle() -> void:
	if _settled:
		return
	_settled = true
	_simulating.erase(self)
	var poses := fallen_pose()
	simulator.physical_bones_stop_simulation()
	for i in poses.size():
		var parent := skeleton.get_bone_parent(i)
		skeleton.set_bone_pose(i, poses[i] if parent < 0 else poses[parent].affine_inverse() * poses[i])
	simulator.queue_free()


## Every bone's pose in the skeleton's space as the ragdoll lies now. Read from the physics
## bodies: the skeleton's own poses never see what the simulator does. Bones without a body
## (shoulders, hands) keep their place on their parent; parents come before children.
func fallen_pose() -> Array[Transform3D]:
	var to_skeleton := skeleton.global_transform.affine_inverse()
	var out: Array[Transform3D] = []
	for i in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(i)
		var bone := simulator.get_node_or_null(NodePath(skeleton.get_bone_name(i))) as PhysicalBone3D if is_instance_valid(simulator) else null
		if bone != null:
			out.append(to_skeleton * bone.global_transform * bone.body_offset.affine_inverse())
		elif parent >= 0:
			out.append(out[parent] * skeleton.get_bone_pose(i))
		else:
			out.append(skeleton.get_bone_pose(i))
	return out


func _add_bones(cfg: Dictionary) -> void:
	simulator = PhysicalBoneSimulator3D.new()
	simulator.name = "Ragdoll"
	skeleton.add_child(simulator)
	var made: Array[PhysicalBone3D] = []
	var bones: Dictionary = cfg["bones"]
	for bone_name: String in bones:
		if skeleton.find_bone(bone_name) < 0:
			continue
		var spec: Variant = bones[bone_name]
		# Players tweak these: a broken entry costs that bone, not every death.
		if not spec is Dictionary or not Data.require("%s bones.%s" % [CONFIG, bone_name], spec, BONE_REQUIRED):
			continue
		if (spec["size"] as Array).size() != 3 or (spec["centre"] as Array).size() != 3:
			Log.warn(&"player", "%s bones.%s: size and centre need three numbers" % [CONFIG, bone_name])
			continue
		var bone := PhysicalBone3D.new()
		bone.name = bone_name
		bone.bone_name = bone_name
		bone.mass = float(spec["mass"])
		bone.friction = float(cfg["friction"])
		bone.linear_damp = float(cfg["linear_damp"])
		bone.angular_damp = float(cfg["angular_damp"])
		# Debris layer, so bullets, eyes and bodies ignore it. Its mask is everything solid,
		# which includes people and cars (they share the solid layer): it can lean on them.
		bone.collision_layer = PhysicsLayers.DEBRIS
		bone.collision_mask = PhysicsLayers.SOLID | PhysicsLayers.GLASS
		var swing := float(spec["swing"])
		if swing > 0.0:
			bone.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
			bone.set(&"joint_constraints/swing_span", swing)
			bone.set(&"joint_constraints/twist_span", float(spec["twist"]))
		var size: Array = spec["size"]
		var centre: Array = spec["centre"]
		var box := BoxShape3D.new()
		box.size = Vector3(float(size[0]), float(size[1]), float(size[2]))
		var shape := CollisionShape3D.new()
		shape.shape = box
		shape.position = Vector3(float(centre[0]), float(centre[1]), float(centre[2]))
		bone.add_child(shape)
		simulator.add_child(bone)
		made.append(bone)
	# Neighbouring parts overlap at the joints; they must not push each other apart.
	for a in made.size():
		for b in range(a + 1, made.size()):
			made[a].add_collision_exception_with(made[b])
