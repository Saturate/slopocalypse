class_name VoxPiece
extends Node3D
## Any voxel generator from the kit, built and stood in the world with collision on one
## static body on the physics server. The boxes are the generator's own `collision(params)`
## where it has one (a lattice is mostly air), otherwise its voxels merged into boxes
## (`VoxelModel.collision_boxes`) with glass and furniture left out so rounds and eyes pass
## windows. A generator with `ladder_box(params)` and `ladder_into()` has its ladder added to
## `Ladders` while the piece stands. Hand-made city blocks and map sites are made of these.

## The generator's class name (`VoxShed`, `VoxApartment`...) and its parameters.
var generator := ""
var params: Dictionary = {}
## The built model, kept only where it is drawn.
var model: VoxelModel

var _body := RID()
var _shapes: Array[RID] = []
var _visual := DisplayServer.get_name() != "headless"


func _ready() -> void:
	var gen := VoxCatalog.by_name(generator)
	if gen == null:
		return
	var own_boxes := gen.has_method(&"collision")
	# A server with the boxes listed has no use for the voxels.
	var built: VoxelModel = gen.build(params) if _visual or not own_boxes else null
	var glass := VoxMaterials.index_of("window_glass")
	var boxes: Array = []
	if own_boxes:
		boxes = gen.call(&"collision", params)
	elif built != null:
		boxes = built.collision_boxes(PackedInt32Array([glass, VoxMaterials.index_of("furniture")]))
	_body = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_collision_layer(_body, PhysicsLayers.SOLID)
	PhysicsServer3D.body_set_collision_mask(_body, 0)
	PhysicsServer3D.body_attach_object_instance_id(_body, get_instance_id())
	for box: AABB in boxes:
		var shape := PhysicsServer3D.box_shape_create()
		PhysicsServer3D.shape_set_data(shape, box.size / 2.0)
		PhysicsServer3D.body_add_shape(_body, shape, Transform3D(Basis.IDENTITY, box.get_center()))
		_shapes.append(shape)
	PhysicsServer3D.body_set_space(_body, get_world_3d().space)
	PhysicsServer3D.body_set_state(_body, PhysicsServer3D.BODY_STATE_TRANSFORM, global_transform)
	if gen.has_method(&"ladder_box") and gen.has_method(&"ladder_into"):
		var climb: AABB = gen.call(&"ladder_box", params)
		var into: Vector3 = gen.call(&"ladder_into")
		Ladders.add(self, global_transform * Transform3D(Basis.IDENTITY, climb.get_center()), climb.size / 2.0, global_basis * into)
	if _visual and built != null:
		model = built
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
	Ladders.remove(self)
	if _body.is_valid():
		PhysicsServer3D.free_rid(_body)
		_body = RID()
	for shape in _shapes:
		PhysicsServer3D.free_rid(shape)
	_shapes.clear()
