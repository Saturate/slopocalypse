class_name VoxPiece
extends Node3D
## Any voxel generator from the kit, built and stood in the world with collision: its voxels
## merged into boxes (`VoxelModel.collision_boxes`) on one static body on the physics server,
## glass and furniture left out so rounds and eyes pass windows. Hand-made city blocks are
## made of these.

## The generator's class name (`VoxShed`, `VoxApartment`...) and its parameters.
var generator := ""
var params: Dictionary = {}
var model: VoxelModel

var _body := RID()
var _shapes: Array[RID] = []
var _visual := DisplayServer.get_name() != "headless"


func _ready() -> void:
	var gen := CityBlock.generators().get(generator) as VoxGenerator
	if gen == null:
		return
	model = gen.build(params)
	if model == null:
		return
	var glass := VoxMaterials.index_of("window_glass")
	_body = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_collision_layer(_body, PhysicsLayers.SOLID)
	PhysicsServer3D.body_set_collision_mask(_body, 0)
	PhysicsServer3D.body_attach_object_instance_id(_body, get_instance_id())
	for box: AABB in model.collision_boxes(PackedInt32Array([glass, VoxMaterials.index_of("furniture")])):
		var shape := PhysicsServer3D.box_shape_create()
		PhysicsServer3D.shape_set_data(shape, box.size / 2.0)
		PhysicsServer3D.body_add_shape(_body, shape, Transform3D(Basis.IDENTITY, box.get_center()))
		_shapes.append(shape)
	PhysicsServer3D.body_set_space(_body, get_world_3d().space)
	PhysicsServer3D.body_set_state(_body, PhysicsServer3D.BODY_STATE_TRANSFORM, global_transform)
	if _visual:
		model.set_clear_materials(PackedInt32Array([glass]))
		var mesh := VoxelChunkedMesh.new()
		mesh.name = "Mesh"
		mesh.layered = true
		mesh.model = model
		add_child(mesh)
		mesh.refresh()


func shape_count() -> int:
	return _shapes.size()


func _exit_tree() -> void:
	if _body.is_valid():
		PhysicsServer3D.free_rid(_body)
		_body = RID()
	for shape in _shapes:
		PhysicsServer3D.free_rid(shape)
	_shapes.clear()
