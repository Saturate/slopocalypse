class_name DemolitionCharge
extends Node3D
## A placed charge. Blinks while the fuse burns, then the server detonates it: damages
## everything with health inside the radius and announces an `explosion`, which the world
## module turns into a crater and clients turn into flash, dust and debris.

var stats: Dictionary = {}
var owner_player: Node

var _fuse := 0.0
var _light := OmniLight3D.new()


func _ready() -> void:
	_fuse = stats["fuse_seconds"]
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.22, 0.12, 0.16)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.3, 0.22)
	box.material = mat
	body.mesh = box
	add_child(body)
	_light.light_color = Color(1.0, 0.15, 0.1)
	_light.omni_range = 1.5
	_light.position = Vector3(0, 0.1, 0)
	add_child(_light)


func _process(_delta: float) -> void:
	# Blinks faster as the fuse runs down.
	var rate := lerpf(3.0, 14.0, 1.0 - _fuse / float(stats["fuse_seconds"]))
	_light.light_energy = 2.0 if fmod(Time.get_ticks_msec() / 1000.0 * rate, 1.0) < 0.5 else 0.0


func _physics_process(delta: float) -> void:
	_fuse -= delta
	if _fuse <= 0.0 and multiplayer.is_server():
		server_explode()


## Server only.
func server_explode() -> void:
	var radius: float = stats["radius"]
	var centre := global_position
	# The placer may have left or died during the fuse; the blast still happens, unattributed.
	var source: Node = owner_player if is_instance_valid(owner_player) else null
	var shape := SphereShape3D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, centre)
	var damaged: Array[HealthComponent] = []
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 64):
		var collider: Object = hit["collider"]
		var health := HealthComponent.find_on(collider as Node) if collider is Node else null
		if health == null or health in damaged:
			continue
		damaged.append(health)
		var holder := health.get_parent() as Node3D
		var distance := holder.global_position.distance_to(centre) if holder != null else 0.0
		# Full damage at the centre, falling off to a quarter at the edge.
		var falloff := lerpf(1.0, 0.25, clampf(distance / radius, 0.0, 1.0))
		health.server_apply_damage(float(stats["damage"]) * falloff, source)
	EventBus.publish(&"explosion", {"position": centre, "radius": radius, "source": source})
	queue_free()
