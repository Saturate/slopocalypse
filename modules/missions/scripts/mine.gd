class_name Mine
extends Node3D
## A hazard in a mission zone, created by the server and replicated by the missions module's
## spawner: a buried mine, or a tripwire across a doorway. Step within the trigger radius
## of a mine (or walk through a wire) and it clicks, then goes off a moment later. A player
## crouching close by sees a mine glint; F while crouched next to it disarms it; a bullet
## hitting it sets it off. The server decides everything; clients only show it.

const BODY_RADIUS := 0.14
const BODY_HEIGHT := 0.05
const METAL := Color(0.3, 0.32, 0.28)
const WIRE := Color(0.75, 0.75, 0.7)
const GLINT := Color(1.0, 0.95, 0.75)

## "mine" or "wire". A wire runs from this node's position to `wire_end`.
var kind := "mine"
var wire_end := Vector3.ZERO
## Numbers from the mission data: `{trigger_radius, delay, blast_radius, damage,
## reveal_range, disarm_range}`.
var cfg: Dictionary = {}

var _armed := true
var _fuse := -1.0
var _glint: MeshInstance3D


func _ready() -> void:
	add_to_group(&"mines")
	if DisplayServer.get_name() == "headless":
		return
	if kind == "wire":
		_build_wire()
	else:
		_build_mine()


func _build_mine() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = BODY_RADIUS
	mesh.bottom_radius = BODY_RADIUS
	mesh.height = BODY_HEIGHT
	var mat := StandardMaterial3D.new()
	mat.albedo_color = METAL
	mat.metallic = 0.6
	mat.roughness = 0.5
	mesh.material = mat
	var body := MeshInstance3D.new()
	body.mesh = mesh
	# Mostly buried: only the top shows, and only up close.
	body.position.y = -BODY_HEIGHT * 0.3
	add_child(body)
	_glint = MeshInstance3D.new()
	var dot := SphereMesh.new()
	dot.radius = 0.035
	dot.height = 0.07
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = GLINT
	glow.emission_enabled = true
	glow.emission = GLINT
	glow.emission_energy_multiplier = 3.0
	dot.material = glow
	_glint.mesh = dot
	_glint.position.y = 0.04
	_glint.visible = false
	add_child(_glint)


func _build_wire() -> void:
	var length := global_position.distance_to(wire_end) if is_inside_tree() else wire_end.length()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.008, 0.008, maxf(length, 0.1))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = WIRE
	mat.metallic = 0.8
	mesh.material = mat
	var line := MeshInstance3D.new()
	line.mesh = mesh
	add_child(line)
	line.global_position = (global_position + wire_end) / 2.0
	if length > 0.01:
		line.look_at(wire_end, Vector3.UP)


func _process(_delta: float) -> void:
	if _glint == null:
		return
	var me := _local_player()
	var near := me != null and me.global_position.distance_to(global_position) < float(cfg.get("reveal_range", 4.0))
	var crouched := me != null and (me as PlayerController).intent().crouch
	_glint.visible = near and crouched and fmod(Time.get_ticks_msec() / 1000.0, 1.2) < 0.25


func _local_player() -> Node3D:
	if not Net.has_local_player():
		return null
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		if int(node.get_meta(&"peer_id", 0)) == Net.local_peer_id():
			return node as Node3D
	return null


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or not _armed and _fuse < 0.0:
		return
	if _fuse >= 0.0:
		_fuse -= delta
		if _fuse <= 0.0:
			server_detonate()
		return
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var p := node as Node3D
		if p != null and not p.get_meta(&"dead", false) and _touches(p.global_position):
			server_trigger()
			return


func _touches(at: Vector3) -> bool:
	var reach := float(cfg.get("trigger_radius", 0.9))
	if kind == "wire":
		var feet := at + Vector3.UP * 0.2
		return distance_to_segment(feet, global_position, wire_end) < reach * 0.4
	return Vector2(at.x - global_position.x, at.z - global_position.z).length() < reach and absf(at.y - global_position.y) < 1.5


static func distance_to_segment(point: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((point - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return point.distance_to(a + ab * t)


func is_armed() -> bool:
	return _armed


## Server: it clicks; it goes off after the delay.
func server_trigger() -> void:
	if not _armed:
		return
	_armed = false
	_fuse = float(cfg.get("delay", 0.6))
	Net.server_broadcast(&"missions.mine_clicked", {"position": global_position})


## Server: it goes off now, hurting everything with health within the blast radius (full at
## the centre, a quarter at the edge), and is gone.
func server_detonate() -> void:
	_armed = false
	_fuse = -1.0
	var radius := float(cfg.get("blast_radius", 3.0))
	var damage := float(cfg.get("damage", 90.0))
	var shape := SphereShape3D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, global_position)
	var hurt: Array[HealthComponent] = []
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 32):
		var collider: Object = hit["collider"]
		var health := HealthComponent.find_on(collider as Node) if collider is Node else null
		if health == null or health in hurt:
			continue
		hurt.append(health)
		var holder := health.get_parent() as Node3D
		var d := holder.global_position.distance_to(global_position) if holder != null else 0.0
		health.server_apply_damage(damage * lerpf(1.0, 0.25, clampf(d / radius, 0.0, 1.0)), self)
	Net.server_broadcast(&"explosion", {"position": global_position, "radius": radius * 0.6, "source": null})
	queue_free()


## Server: made safe and removed.
func server_disarm() -> void:
	_armed = false
	_fuse = -1.0
	Net.server_broadcast(&"missions.mine_disarmed", {"position": global_position})
	queue_free()
