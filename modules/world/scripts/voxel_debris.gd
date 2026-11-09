class_name VoxelDebris
extends RefCounted
## Little voxel cubes thrown out of whatever breaks (bark off a trunk, dirt from a crater,
## asphalt from the road). Client-only and purely for show: a one-shot particle burst that
## frees itself when the last cube has landed.

const LIFETIME := 1.6
const CUBE := 0.12


## `count` cubes of `colour` burst from `at`, thrown roughly along `towards` at about
## `speed` metres per second.
static func burst(parent: Node, at: Vector3, towards: Vector3, colour: Color, count: int, speed: float) -> CPUParticles3D:
	if count <= 0 or not parent.is_inside_tree():
		return null
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = count
	p.lifetime = LIFETIME
	var box := BoxMesh.new()
	box.size = Vector3.ONE * CUBE
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	box.material = material
	p.mesh = box
	p.direction = towards if towards.length() > 0.01 else Vector3.UP
	p.spread = 55.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	p.local_coords = false
	parent.add_child(p)
	p.global_position = at
	p.finished.connect(p.queue_free)
	p.emitting = true
	return p
