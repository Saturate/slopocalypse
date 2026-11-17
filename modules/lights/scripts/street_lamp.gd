class_name StreetLamp
extends StaticBody3D
## A voxel street lamp (VoxStreetLamp) whose bulb glows and lights the ground under it. One
## round on the bulb shatters it, by the `bulb` material's rules (window glass): the glow and
## the light go out for good. The server decides that (LightsModule); this only shows it.

## Stable across server and clients: lamps are numbered as they are placed.
var lamp_id := 0
## The `lamp` block of lights.json.
var config: Dictionary = {}
var broken := false

var _model: VoxelModel
var _mesh: VoxelChunkedMesh
var _bulb_box := AABB()
var _bulb_shape: CollisionShape3D
var _glow: MeshInstance3D
var _light: OmniLight3D
var _visual := DisplayServer.get_name() != "headless"


func _ready() -> void:
	collision_layer = PhysicsLayers.SOLID
	var h := float(config.get("height", 4.5))
	var reach := float(config.get("reach", 1.1))
	_model = VoxStreetLamp.new().build({"seed": lamp_id + 1, "height": h, "reach": reach})
	var bulb := VoxMaterials.index_of("bulb")
	var boxes: Array = _model.components(bulb)
	if not boxes.is_empty():
		_bulb_box = boxes[0]
	var post := VoxStreetLamp.POST
	_add_box(AABB(Vector3(-VoxStreetLamp.FOOT_SIZE.x / 2.0, 0.0, -VoxStreetLamp.FOOT_SIZE.z / 2.0), Vector3(VoxStreetLamp.FOOT_SIZE.x, VoxStreetLamp.FOOT_SIZE.y, VoxStreetLamp.FOOT_SIZE.z)))
	_add_box(AABB(Vector3(-post / 2.0, 0.0, -post / 2.0), Vector3(post, h, post)))
	var head := VoxStreetLamp.HEAD
	_add_box(AABB(Vector3(-post / 2.0, h - head.y, -head.z / 2.0), Vector3(reach + head.x / 2.0 + post / 2.0, head.y, head.z)))
	_bulb_shape = _add_box(_bulb_box)
	if not _visual:
		return
	_model.set_clear_materials(PackedInt32Array([bulb]))
	_mesh = VoxelChunkedMesh.new()
	_mesh.name = "Mesh"
	_mesh.layered = true
	_mesh.model = _model
	add_child(_mesh)
	_mesh.refresh()
	var colour := _colour(config.get("light_colour", [1.0, 0.8, 0.55]))
	# The bulb's light seen through its glass: a lit block just inside it. Emission past 1 is
	# what blooms; an unshaded material would clamp it.
	_glow = MeshInstance3D.new()
	_glow.name = "Glow"
	var box := BoxMesh.new()
	box.size = _bulb_box.size * 0.92
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.BLACK
	material.emission_enabled = true
	material.emission = colour
	material.emission_energy_multiplier = float(config.get("glow_energy", 3.0))
	box.material = material
	_glow.mesh = box
	_glow.position = _bulb_box.get_center()
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_glow)
	_light = OmniLight3D.new()
	_light.name = "Light"
	_light.light_color = colour
	_light.light_energy = float(config.get("light_energy", 2.5))
	_light.omni_range = float(config.get("light_range", 16.0))
	_light.shadow_enabled = true
	# Just under the bulb, so the lamp's own head doesn't shadow the street.
	_light.position = _bulb_box.get_center() + Vector3.DOWN * (_bulb_box.size.y + 0.05)
	_light.add_to_group(LightBudget.GROUP)
	add_child(_light)


static func _colour(rgb: Array) -> Color:
	return Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))


func _add_box(box: AABB) -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = box.size
	shape.shape = b
	shape.position = box.get_center()
	add_child(shape)
	return shape


## Whether a round that struck at `point` (world) struck the bulb.
func hits_bulb(point: Vector3) -> bool:
	return not broken and _bulb_box.size != Vector3.ZERO and _bulb_box.grow(0.03).has_point(to_local(point))


func is_lit() -> bool:
	return not broken and _light != null


## Everywhere: the bulb is gone, its glow and light out; with `animate`, glass flies.
func break_bulb(animate := true) -> void:
	if broken:
		return
	broken = true
	_bulb_shape.set_deferred(&"disabled", true)
	if _light != null:
		_light.queue_free()
		_light = null
	if _glow != null:
		_glow.queue_free()
		_glow = null
	_model.carve_box(_bulb_box.position - Vector3.ONE * 0.01, _bulb_box.end + Vector3.ONE * 0.01)
	if _mesh != null:
		_mesh.refresh()
	if animate and _visual and is_inside_tree():
		_shards()
		# The audio module plays breaking surfaces by material from this topic.
		EventBus.publish(&"missions.surface_broke", {"position": global_transform * _bulb_box.get_center(), "material": "bulb", "count": 1})


func _shards() -> void:
	var burst := CPUParticles3D.new()
	burst.name = "Shards"
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.amount = 24
	burst.lifetime = 1.4
	burst.direction = Vector3.DOWN
	burst.spread = 70.0
	burst.initial_velocity_min = 1.0
	burst.initial_velocity_max = 3.0
	burst.gravity = Vector3(0, -9.8, 0)
	var shard := BoxMesh.new()
	shard.size = Vector3(0.03, 0.006, 0.03)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.9, 0.92, 0.95)
	material.metallic = 0.2
	material.roughness = 0.1
	shard.material = material
	burst.mesh = shard
	burst.position = _bulb_box.get_center()
	add_child(burst)
	burst.emitting = true
	burst.finished.connect(burst.queue_free)
