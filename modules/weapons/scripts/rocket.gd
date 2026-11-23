class_name Rocket
extends Node3D
## A rocket in flight. The server spawns it (through the weapons module's spawner, so every
## instance has it) with where it starts and how fast it goes; every instance flies it the
## same way, falling a little. On the server it sweeps ahead each tick and, once it has flown
## `arm_distance`, blows up on the first thing it meets (or at the end of `lifetime`) through
## the same explosion path as charges; before that a hit just stops it (a dud). The server
## freeing it takes it away everywhere.

var velocity := Vector3.ZERO
## The shooter (server only): its body doesn't stop its own rocket.
var shooter: Node3D
var cfg: Dictionary = {}

var _flown := 0.0
var _age := 0.0
var _gravity := Vector3.DOWN * 9.8


func _ready() -> void:
	_gravity = Vector3.DOWN * float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) * float(cfg.get("drop", 0.15))
	if velocity.length_squared() > 0.0:
		look_at(global_position + velocity, Vector3.UP)
	if DisplayServer.get_name() != "headless":
		_build_looks()


func _physics_process(delta: float) -> void:
	var t := Prof.start()
	_fly(delta)
	Prof.stop(&"weapons/rocket:physics", t)


func _fly(delta: float) -> void:
	_age += delta
	velocity += _gravity * delta
	var from := global_position
	var to := from + velocity * delta
	if multiplayer.is_server():
		var query := PhysicsRayQueryParameters3D.create(from, to, PhysicsLayers.BULLETS)
		if shooter is CollisionObject3D:
			query.exclude = [(shooter as CollisionObject3D).get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			_flown += from.distance_to(hit["position"])
			if _flown >= float(cfg.get("arm_distance", 4.0)):
				server_explode(hit["position"] - velocity.normalized() * 0.2)
			else:
				queue_free()
			return
		if _age >= float(cfg.get("lifetime", 6.0)):
			server_explode(to)
			return
	_flown += from.distance_to(to)
	global_position = to
	if velocity.length_squared() > 0.0:
		look_at(to + velocity, Vector3.UP)


## Server only: blows up at `at`: everyone in reach hurt (less at the edge), then the shared
## explosion everyone sees, which breaks buildings, digs and throws debris.
func server_explode(at: Vector3) -> void:
	var radius := float(cfg.get("radius", 2.8))
	var shape := SphereShape3D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, at)
	var damaged: Array[HealthComponent] = []
	var source: Node = shooter if is_instance_valid(shooter) else null
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 64):
		var collider: Object = hit["collider"]
		var health := HealthComponent.find_on(collider as Node) if collider is Node else null
		if health == null or health in damaged:
			continue
		damaged.append(health)
		var body := health.get_parent() as Node3D
		var distance := body.global_position.distance_to(at) if body != null else 0.0
		health.server_apply_damage(float(cfg.get("damage", 160.0)) * lerpf(1.0, 0.25, clampf(distance / radius, 0.0, 1.0)), source)
	Net.server_broadcast(&"explosion", {"position": at, "radius": radius, "source": source})
	queue_free()


## A slim olive body with a pointed nose and four fins, and a smoke trail behind.
func _build_looks() -> void:
	var st := LowPoly.begin()
	var body := Color(0.32, 0.35, 0.24)
	LowPoly.cylinder(st, 0.045, 0.5, 10, Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0.0, 0.0, 0.05)), body)
	LowPoly.cylinder(st, 0.045, 0.16, 10, Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(0.0, 0.0, -0.2)), Color(0.25, 0.25, 0.26), 0.0)
	for i in 4:
		var a := TAU * float(i) / 4.0
		LowPoly.box(st, Vector3(0.012, 0.09, 0.1), Transform3D(Basis(Vector3.BACK, a), Vector3(0.0, 0.0, 0.26)) * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.06, 0.0)), Color(0.2, 0.2, 0.2))
	var mesh := MeshInstance3D.new()
	mesh.mesh = LowPoly.finish(st, LowPoly.material(0.6, 0.2))
	add_child(mesh)
	var flame := OmniLight3D.new()
	flame.light_color = Color(1.0, 0.7, 0.35)
	flame.light_energy = 1.5
	flame.omni_range = 3.0
	flame.position = Vector3(0.0, 0.0, 0.35)
	add_child(flame)
	var trail := CPUParticles3D.new()
	trail.amount = 60
	trail.lifetime = 1.2
	trail.local_coords = false
	trail.position = Vector3(0.0, 0.0, 0.35)
	trail.direction = Vector3(0.0, 0.0, 1.0)
	trail.spread = 12.0
	trail.initial_velocity_min = 0.5
	trail.initial_velocity_max = 1.5
	trail.gravity = Vector3(0.0, 0.4, 0.0)
	trail.scale_amount_min = 0.15
	trail.scale_amount_max = 0.35
	var puff := BoxMesh.new()
	puff.size = Vector3.ONE * 0.25
	var smoke := StandardMaterial3D.new()
	smoke.albedo_color = Color(0.75, 0.74, 0.72, 0.5)
	smoke.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke.vertex_color_use_as_albedo = true
	puff.material = smoke
	trail.mesh = puff
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.7))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	trail.color_ramp = fade
	add_child(trail)
