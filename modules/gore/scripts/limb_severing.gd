class_name LimbSevering
extends Node
## Limbs come off (#387), on each client from what it saw; nothing is synced. A ragdoll that
## has just fallen (`player.corpse_fell`) is matched with the killing blow, which may arrive a
## moment before or after it: a blast (`explosion`) within `blast_sever_radius` takes the
## limbs nearest it, and a killing shot (`weapon.fired`) that dealt at least
## `shot_sever_damage` to an arm or leg cuts at the joint above the hit, `shot_sever_chance` of
## the time (LimbRules). The ragdoll loses the limb (`Corpse.remove_limb`), a red cap shows at
## the stump, and the piece, cut from
## the body's own mesh (LimbPieces), flies off as a small rigid body that bleeds and leaves a
## few marks where it lands. Pieces go with their corpse; at most `max_limbs` lie about.
##
## With the "Blood" setting off nothing comes off.

## Its own fields in gore.json, checked apart from blood's: a player's tweaked gore.json from
## before limbs (tweaks replace the whole file) lacks them, and blood should still work.
const REQUIRED := {
	"shot_sever_damage": TYPE_FLOAT, "shot_sever_chance": TYPE_FLOAT, "shot_sever_depth": TYPE_FLOAT,
	"headshot_sever": TYPE_BOOL, "blast_sever_radius": TYPE_FLOAT, "blast_max_limbs": TYPE_FLOAT,
	"blast_all_limbs_within": TYPE_FLOAT, "sever_window_seconds": TYPE_FLOAT, "limb_fling": TYPE_FLOAT,
	"limb_fling_up": TYPE_FLOAT, "limb_spin": TYPE_FLOAT, "limb_mass": TYPE_FLOAT, "limb_damp": TYPE_FLOAT,
	"limb_friction": TYPE_FLOAT, "max_limbs": TYPE_FLOAT, "stump_spray_count": TYPE_FLOAT,
	"limb_bleed_seconds": TYPE_FLOAT, "limb_bleed_interval": TYPE_FLOAT, "limb_bleed_drops": TYPE_FLOAT,
	"limb_trail_marks": TYPE_FLOAT, "limb_trail_mark_size": TYPE_FLOAT,
}
const GROUP := &"gore_limbs"
## Meta on a corpse once its killing blow has been looked at, so it is cut at most once.
const SEVERED := &"gore_severed"
## The body every soldier and player wears, cut up while loading so no death builds a mesh.
const BODY := "res://modules/player/scenes/player_body.tscn"
const MESHES: Array[String] = ["Mesh", "Arms"]
## A stump cap covers this share of the limb's thickness, and is this thick.
const CAP_SHARE := 0.85
const CAP_DEPTH := 0.03
## How far down from a landing piece the ground is looked for, and from how far above.
const TRAIL_DOWN := 1.5
const TRAIL_UP := 0.3
## Frames the warm-up piece is drawn, and how far in front of the camera, at what scale.
const WARM_FRAMES := 2
const WARM_AHEAD := 1.0
const WARM_SCALE := 0.001
## Bones a shot can take an arm by.
const ARM_BONES: Array[String] = ["UpperArm_L", "LowerArm_L", "Hand_L", "UpperArm_R", "LowerArm_R", "Hand_R"]

## Supplies the spray and the marks; without it pieces still come off, unbloodied.
var blood: BloodEffects

## Just-fallen ragdolls waiting for their killing blow: {corpse, body, velocity, at, frame}.
var _fallen: Array[Dictionary] = []
## Body instance id -> its latest hit: {point, direction, damage, at}.
var _hits: Dictionary = {}
## Recent blasts: {position, at}.
var _blasts: Array[Dictionary] = []
## Loose pieces, oldest first, and per piece what it still has to do.
var _pieces: Array[RigidBody3D] = []
var _caps: Array[Node3D] = []
var _cap_meshes: Dictionary = {}
## Held so the resource cache keeps the body's meshes, which the cut pieces are filed under:
## dropped, the next body would load new meshes and every death would cut its pieces again.
var _body_scene: PackedScene
## A piece drawn too small to see for a frame while loading, so its draw is set up then.
var _warm: MeshInstance3D
var _warm_frames := WARM_FRAMES
var _rng := RandomNumberGenerator.new()

static var _config: Dictionary = {}
static var _loaded := false


## The limb values from gore.json, or empty (after logging what is missing) when they are not
## all there; then nothing comes off.
static func config() -> Dictionary:
	if not _loaded:
		use_config(Data.load_json(BloodEffects.CONFIG))
	return _config


## Takes `data` as the limb values if it has them all, else none (tests and tweaks).
static func use_config(data: Variant) -> void:
	_loaded = true
	_config = data if data is Dictionary and Data.require(BloodEffects.CONFIG, data, REQUIRED) else {}


func _ready() -> void:
	# A player's own gore.json from before limbs lacks their values: blood still works, limbs
	# stay on.
	if config().is_empty() or BloodEffects.config().is_empty():
		set_process(false)
		return
	_rng.randomize()
	_prepare()
	EventBus.subscribe(&"player.corpse_fell", _on_corpse_fell)
	EventBus.subscribe(&"weapon.fired", _on_fired)
	EventBus.subscribe(&"explosion", _on_explosion)
	EventBus.subscribe(&"settings.changed", _on_settings_changed)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"player.corpse_fell", _on_corpse_fell)
	EventBus.unsubscribe(&"weapon.fired", _on_fired)
	EventBus.unsubscribe(&"explosion", _on_explosion)
	EventBus.unsubscribe(&"settings.changed", _on_settings_changed)


## Loose pieces still lying about, oldest first.
func pieces() -> Array[RigidBody3D]:
	_prune()
	return _pieces


func _process(delta: float) -> void:
	if config().is_empty() or _warm == null and _fallen.is_empty() and _pieces.is_empty() and _hits.is_empty() and _blasts.is_empty():
		return
	var prof := Prof.start()
	_warm_up()
	resolve()
	_bleed(delta)
	Prof.stop(&"gore/limbs", prof)


## Hits still remembered (pruned once older than `sever_window_seconds`).
func remembered_hits() -> int:
	return _hits.size()


## Cuts the pieces of every limb of the body every death needs, before any death does.
func _prepare() -> void:
	_body_scene = load(BODY) as PackedScene
	if _body_scene == null:
		return
	var body := _body_scene.instantiate()
	var skeleton := body.get_node_or_null("Skeleton") as Skeleton3D
	if skeleton != null:
		for mesh_name in MESHES:
			var source := skeleton.get_node_or_null(mesh_name) as MeshInstance3D
			if source == null:
				continue
			LimbPieces.bone_boxes(source, skeleton)
			for limb: String in LimbRules.LIMBS:
				var cut := LimbPieces.piece(source, skeleton, limb)
				if cut != null and _warm == null:
					_warm = MeshInstance3D.new()
					_warm.name = "WarmPiece"
					_warm.mesh = cut
					_warm.top_level = true
					_warm.visible = false
					add_child(_warm)
					# Caps are blood-red blocks drawn on their own, unlike the drops' multimesh.
					var cap := MeshInstance3D.new()
					cap.mesh = _cap_mesh("", AABB())
					_warm.add_child(cap)
	body.free()


## Draws one piece and a cap, too small to see, in front of the camera for a couple of frames: pieces
## are plain meshes cut from a skinned one, and their first draw would otherwise set up
## pipelines in the middle of a fight.
func _warm_up() -> void:
	if _warm == null or _warm_frames <= 0:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	_warm.visible = true
	_warm.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * WARM_SCALE), camera.global_position - camera.global_basis.z * WARM_AHEAD)
	_warm_frames -= 1
	if _warm_frames == 0:
		_warm.queue_free()
		_warm = null


## Decides for the ragdolls that have fallen since the last frame (all of them when `now`):
## by then the killing blow's events, sent alongside the death, have arrived.
func resolve(now := false) -> void:
	var cfg := config()
	if cfg.is_empty():
		return
	var window := int(float(cfg["sever_window_seconds"]) * 1000.0)
	var clock := Time.get_ticks_msec()
	var frame := Engine.get_process_frames()
	var i := 0
	while i < _fallen.size():
		var entry := _fallen[i]
		if not now and int(entry["frame"]) >= frame:
			i += 1
			continue
		_fallen.remove_at(i)
		var corpse: Variant = entry["corpse"]
		if is_instance_valid(corpse) and not (corpse as Corpse).has_meta(SEVERED):
			_decide(corpse as Corpse, entry, cfg, window, clock)
	if not _blasts.is_empty():
		_blasts = _blasts.filter(func(b: Dictionary) -> bool: return clock - int(b["at"]) <= window)
	for id: int in _hits.keys():
		if clock - int(_hits[id]["at"]) > window:
			_hits.erase(id)


func _on_corpse_fell(p: Dictionary) -> void:
	var corpse := p.get("corpse") as Corpse
	var cfg := config()
	if corpse == null or cfg.is_empty() or not BloodEffects.blood_on() or int(cfg["max_limbs"]) <= 0:
		return
	_fallen.append({"corpse": corpse, "body": p.get("body"), "velocity": p.get("velocity", Vector3.ZERO), "at": Time.get_ticks_msec(), "frame": Engine.get_process_frames()})


func _on_fired(p: Dictionary) -> void:
	var target: Variant = p.get("target")
	if not is_instance_valid(target) or not target is Node3D:
		return
	var from: Vector3 = p.get("from", Vector3.ZERO)
	var to: Vector3 = p.get("to", Vector3.ZERO)
	# What the hit dealt, not the gun's damage: a finishing shot into a nearly dead body
	# takes nothing off.
	var damage := float(p.get("damage", 0.0))
	_hits[(target as Object).get_instance_id()] = {"point": to, "direction": (to - from).normalized(), "damage": damage, "at": Time.get_ticks_msec()}


func _on_explosion(p: Dictionary) -> void:
	_blasts.append({"position": p.get("position", Vector3.ZERO), "at": Time.get_ticks_msec()})


func _on_settings_changed(p: Dictionary) -> void:
	if str(p.get("key", "")) == "blood" and not bool(p.get("value", true)):
		for piece in _pieces:
			if is_instance_valid(piece):
				piece.queue_free()
		for cap in _caps:
			if is_instance_valid(cap):
				cap.queue_free()
		_pieces.clear()
		_caps.clear()


func _decide(corpse: Corpse, entry: Dictionary, cfg: Dictionary, window: int, clock: int) -> void:
	var fell_at := int(entry["at"])
	var velocity: Vector3 = entry["velocity"]
	var hips := _bone_position(corpse, "Hips")
	# A blast that went off with the death wins over a shot; the nearest, if several did.
	var nearest: Variant = null
	for blast in _blasts:
		if absi(int(blast["at"]) - fell_at) > window:
			continue
		if nearest == null or hips.distance_to(blast["position"]) < hips.distance_to((nearest as Dictionary)["position"]):
			nearest = blast
	if nearest != null:
		var centre: Vector3 = (nearest as Dictionary)["position"]
		var distances := {}
		for limb: String in LimbRules.BLAST_LIMBS:
			distances[limb] = _limb_centre(corpse, limb).distance_to(centre)
		var limbs := LimbRules.blast_limbs(hips.distance_to(centre), distances, cfg)
		# A blast too far off to take anything leaves the shot to decide.
		if not limbs.is_empty():
			corpse.set_meta(SEVERED, true)
			for limb in limbs:
				var away := _limb_centre(corpse, limb) - centre
				sever(corpse, limb, away.normalized() if away.length() > 0.01 else Vector3.UP, velocity)
			return
	var body: Variant = entry["body"]
	if not is_instance_valid(body):
		return
	var hit: Variant = _hits.get((body as Object).get_instance_id())
	if not hit is Dictionary or absi(int(hit["at"]) - fell_at) > window or clock - int(hit["at"]) > window:
		return
	corpse.set_meta(SEVERED, true)
	var limb := shot_limb(corpse, hit["point"], hit["direction"], float(hit["damage"]), cfg)
	if not limb.is_empty() and _rng.randf() < float(cfg["shot_sever_chance"]):
		sever(corpse, limb, hit["direction"], velocity)


## The limb a shot that hit `corpse` at `point` going along `direction` would take, before the
## chance: judged a little way into the body (`shot_sever_depth`), since a bullet stops on the
## body's outline, which the arms held out in front of the chest fill. An arm only when the
## point is further out to the side of the spine than that arm's shoulder.
func shot_limb(corpse: Corpse, point: Vector3, direction: Vector3, damage: float, cfg: Dictionary) -> String:
	var inside := point + direction.normalized() * float(cfg["shot_sever_depth"])
	var bone := LimbPieces.nearest_bone(_sources(corpse), corpse.skeleton, inside)
	if bone < 0:
		return ""
	var bone_name := corpse.skeleton.get_bone_name(bone)
	if bone_name in ARM_BONES:
		var shoulder := _bone_position(corpse, "UpperArm_" + bone_name.right(1))
		if _from_spine(corpse, inside) < _from_spine(corpse, shoulder):
			return ""
	return LimbRules.shot_limb(bone_name, damage, cfg)


## How far `point` is out to the side of the spine, along the hips' left-right axis: arms
## held out in front of the chest are close in by this, however far forward they reach.
func _from_spine(corpse: Corpse, point: Vector3) -> float:
	var hips := corpse.skeleton.find_bone("Hips")
	if hips < 0:
		return 0.0
	var pose := corpse.skeleton.global_transform * corpse.skeleton.get_bone_global_pose(hips)
	return absf((point - pose.origin).dot(pose.basis.x.normalized()))


## Takes `limb` off `corpse`: its bones collapse and lose their physics, a cap shows at the
## stump, and the piece flies along `fling` on top of the body's own `velocity`.
func sever(corpse: Corpse, limb: String, fling: Vector3, velocity: Vector3) -> RigidBody3D:
	var cfg := config()
	var skeleton := corpse.skeleton
	var root := skeleton.find_bone(LimbRules.root_bone(limb))
	if root < 0:
		return null
	var joint := (skeleton.global_transform * skeleton.get_bone_global_pose(root)).orthonormalized()
	var piece := _piece(corpse, limb, cfg)
	if piece == null:
		return null
	corpse.add_child(piece)
	piece.global_transform = joint
	# Out from the body as well as along the blow: a piece thrown only along the shot lands
	# under the body falling the same way, and reads as still attached.
	var out := joint.origin - _bone_position(corpse, "Hips")
	out.y = 0.0
	var way := fling.normalized() + (out.normalized() if out.length() > 0.01 else Vector3.ZERO)
	var throw := way.normalized() * float(cfg["limb_fling"]) + Vector3.UP * float(cfg["limb_fling_up"])
	piece.linear_velocity = velocity + throw
	var push := throw.normalized() if throw.length() > 0.01 else Vector3.UP
	var spin := float(cfg["limb_spin"])
	piece.angular_velocity = Vector3(_rng.randf_range(-spin, spin), _rng.randf_range(-spin, spin), _rng.randf_range(-spin, spin))
	_collapse(corpse, limb)
	_cap_stump(corpse, limb, root)
	if blood != null and blood.spray != null:
		blood.spray.spray(joint.origin, push, int(cfg["stump_spray_count"]))
	_pieces.append(piece)
	_prune()
	while _pieces.size() > int(cfg["max_limbs"]):
		_pieces.pop_front().queue_free()
	return piece


func _piece(corpse: Corpse, limb: String, cfg: Dictionary) -> RigidBody3D:
	var piece := RigidBody3D.new()
	piece.name = "Limb"
	piece.add_to_group(GROUP)
	piece.top_level = true
	piece.mass = float(cfg["limb_mass"])
	# Damped and rough, so a piece comes down near its body and stays where it lands instead of
	# sliding down the road.
	piece.linear_damp = float(cfg["limb_damp"])
	piece.angular_damp = float(cfg["limb_damp"])
	var surface := PhysicsMaterial.new()
	surface.friction = float(cfg["limb_friction"])
	surface.rough = true
	piece.physics_material_override = surface
	# Like the ragdoll's bones: it lands on the ground and buildings, and nothing notices it.
	piece.collision_layer = PhysicsLayers.DEBRIS
	piece.collision_mask = PhysicsLayers.SOLID | PhysicsLayers.GLASS
	piece.contact_monitor = true
	piece.max_contacts_reported = 1
	var bounds := AABB()
	var found := false
	# The cap is sized to the cut bone alone: a whole arm's bounds take in the bent forearm.
	var cut_bone := AABB()
	var root := corpse.skeleton.find_bone(LimbRules.root_bone(limb))
	for source in _sources(corpse):
		var mesh := LimbPieces.piece(source, corpse.skeleton, limb)
		if mesh == null:
			continue
		var boxes := LimbPieces.bone_boxes(source, corpse.skeleton)
		if boxes.has(root):
			cut_bone = boxes[root]
		var shown := MeshInstance3D.new()
		shown.mesh = mesh
		# Soldiers wear their side's colours as an override on the body.
		shown.material_override = source.material_override
		BloodEffects.keep_clean(shown)
		piece.add_child(shown)
		bounds = bounds.merge(mesh.get_aabb()) if found else mesh.get_aabb()
		found = true
	if not found:
		piece.free()
		return null
	var box := BoxShape3D.new()
	box.size = bounds.size.max(Vector3.ONE * 0.05)
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position = bounds.get_center()
	piece.add_child(shape)
	var cap := MeshInstance3D.new()
	cap.name = "Cap"
	cap.mesh = _cap_mesh(limb, cut_bone if cut_bone.has_volume() else bounds)
	BloodEffects.keep_clean(cap)
	piece.add_child(cap)
	# Where the cut end faces, from the piece's middle out through the joint.
	piece.set_meta(&"cut", (-bounds.get_center()).normalized())
	piece.set_meta(&"age", 0.0)
	piece.set_meta(&"marks", 0)
	piece.body_entered.connect(_on_piece_landed.bind(piece))
	return piece


func _collapse(corpse: Corpse, limb: String) -> void:
	var bones: Array[StringName] = []
	for bone_name: String in LimbRules.bones(limb):
		bones.append(StringName(bone_name))
	corpse.remove_limb(bones, StringName(LimbRules.root_bone(limb)))


func _cap_stump(corpse: Corpse, limb: String, root: int) -> void:
	var skeleton := corpse.skeleton
	var parent := skeleton.get_bone_parent(root)
	if parent < 0:
		return
	var attach := BoneAttachment3D.new()
	attach.name = "Stump"
	attach.bone_name = skeleton.get_bone_name(parent)
	skeleton.add_child(attach)
	var cap := MeshInstance3D.new()
	cap.mesh = _cap_mesh(limb, AABB())
	cap.transform = Transform3D(Basis(skeleton.get_bone_pose_rotation(root)), skeleton.get_bone_pose_position(root))
	BloodEffects.keep_clean(cap)
	attach.add_child(cap)
	_caps.append(attach)


## A flat red block across the limb at its joint, sized to the limb's thickness there; one per
## limb, shared.
func _cap_mesh(limb: String, bounds: AABB) -> BoxMesh:
	if _cap_meshes.has(limb):
		return _cap_meshes[limb]
	var size := bounds.size if bounds.has_volume() else Vector3.ONE * 0.1
	var across := minf(size.x, size.z) * CAP_SHARE
	var mesh := BoxMesh.new()
	mesh.size = Vector3(across, CAP_DEPTH, across)
	mesh.material = BloodEffects.material(BloodEffects.config())
	if bounds.has_volume():
		_cap_meshes[limb] = mesh
	return mesh


## Pieces bleed for a while as they fly.
func _bleed(delta: float) -> void:
	if blood == null or blood.spray == null:
		return
	var cfg := config()
	var seconds := float(cfg["limb_bleed_seconds"])
	var interval := maxf(float(cfg["limb_bleed_interval"]), 0.01)
	for piece in pieces():
		var age := float(piece.get_meta(&"age", 0.0))
		if age >= seconds:
			continue
		var next := age + delta
		piece.set_meta(&"age", next)
		if floorf(next / interval) > floorf(age / interval):
			var cut: Vector3 = piece.get_meta(&"cut", Vector3.UP)
			blood.spray.spray(piece.global_position, piece.global_basis * cut, int(cfg["limb_bleed_drops"]))


## A mark where a flying piece comes down, a few per piece.
func _on_piece_landed(_other: Node, piece: RigidBody3D) -> void:
	var cfg := config()
	if blood == null or blood.marks == null or not is_instance_valid(piece) or int(piece.get_meta(&"marks", 0)) >= int(cfg["limb_trail_marks"]):
		return
	piece.set_meta(&"marks", int(piece.get_meta(&"marks", 0)) + 1)
	var at := piece.global_position
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * TRAIL_UP, at + Vector3.DOWN * TRAIL_DOWN, PhysicsLayers.BULLETS)
	var hit := piece.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var size := float(cfg["limb_trail_mark_size"])
	var along := piece.linear_velocity if piece.linear_velocity.length() > 0.1 else Vector3.FORWARD
	blood.marks.add_mark(hit["position"], hit["normal"], along, size, size)


func _prune() -> void:
	_pieces = _pieces.filter(func(p: Variant) -> bool: return is_instance_valid(p) and not (p as Node).is_queued_for_deletion())
	_caps = _caps.filter(func(c: Variant) -> bool: return is_instance_valid(c))


func _sources(corpse: Corpse) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for mesh_name in MESHES:
		var source := corpse.skeleton.get_node_or_null(NodePath(mesh_name)) as MeshInstance3D
		if source != null and source.mesh != null and source.skin != null:
			out.append(source)
	return out


func _bone_position(corpse: Corpse, bone_name: String) -> Vector3:
	var bone := corpse.skeleton.find_bone(bone_name)
	if bone < 0:
		return corpse.global_position
	return (corpse.skeleton.global_transform * corpse.skeleton.get_bone_global_pose(bone)).origin


## Middle of a limb as it lies: halfway down its root bone towards the next one.
func _limb_centre(corpse: Corpse, limb: String) -> Vector3:
	var chain := LimbRules.bones(limb)
	var start := _bone_position(corpse, String(chain[0]))
	if chain.size() < 2:
		return start
	return start.lerp(_bone_position(corpse, String(chain[1])), 0.5)
