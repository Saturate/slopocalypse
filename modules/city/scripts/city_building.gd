class_name CityBuilding
extends Node3D
## One apartment block (VoxApartment) you can walk into: in through the front door, up the
## stairs, along the flats, out onto a flat roof. Its collision is the model's own voxels
## merged into boxes (`VoxelModel.collision_boxes`), so doors, windows and stairs are open
## exactly where they are drawn; glass and furniture are left out, so rounds and eyes pass
## windows. The boxes go straight to the physics server on one static body: a block has a few
## thousand, and a node each would cost far more than the shapes themselves.
##
## The street side (front doors) faces -Z.

## VoxApartment's parameters.
var params: Dictionary = {}
var model: VoxelModel

var _body := RID()
var _shapes: Array[RID] = []
var _visual := DisplayServer.get_name() != "headless"


func _ready() -> void:
	var t := Prof.start()
	model = VoxApartment.new().build(params)
	var skip := PackedInt32Array([VoxMaterials.index_of("window_glass"), VoxMaterials.index_of("furniture")])
	_body = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_collision_layer(_body, PhysicsLayers.SOLID)
	PhysicsServer3D.body_set_collision_mask(_body, 0)
	# Rays that hit it report this node as their collider.
	PhysicsServer3D.body_attach_object_instance_id(_body, get_instance_id())
	for box: AABB in model.collision_boxes(skip):
		var shape := PhysicsServer3D.box_shape_create()
		PhysicsServer3D.shape_set_data(shape, box.size / 2.0)
		PhysicsServer3D.body_add_shape(_body, shape, Transform3D(Basis.IDENTITY, box.get_center()))
		_shapes.append(shape)
	PhysicsServer3D.body_set_space(_body, get_world_3d().space)
	PhysicsServer3D.body_set_state(_body, PhysicsServer3D.BODY_STATE_TRANSFORM, global_transform)
	set_notify_transform(true)
	if _visual:
		model.set_clear_materials(PackedInt32Array([VoxMaterials.index_of("window_glass")]))
		var mesh := VoxelChunkedMesh.new()
		mesh.name = "Mesh"
		mesh.layered = true
		mesh.model = model
		add_child(mesh)
		mesh.refresh()
	Prof.stop(&"city/building", t)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and _body.is_valid():
		PhysicsServer3D.body_set_state(_body, PhysicsServer3D.BODY_STATE_TRANSFORM, global_transform)
	elif what == NOTIFICATION_PREDELETE:
		_free_physics()


func _exit_tree() -> void:
	_free_physics()


func _free_physics() -> void:
	if _body.is_valid():
		PhysicsServer3D.free_rid(_body)
		_body = RID()
	for shape in _shapes:
		PhysicsServer3D.free_rid(shape)
	_shapes.clear()


func shape_count() -> int:
	return _shapes.size()


## The plan in metres (VoxApartment.layout), for placing people and checking reach.
func plan() -> Dictionary:
	return VoxApartment.new().layout(params)
