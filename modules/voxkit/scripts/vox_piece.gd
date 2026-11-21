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
## The built model, kept only where it is drawn (and not `shared`).
var model: VoxelModel
## For pieces put up many times alike (pylons, poles): drawn with one mesh per generator,
## parameters and detail step, kept until `clear_shared`, and no model kept. The meshes are
## built here, at most one a frame across all pieces (a voxel model can't be touched off the
## main thread), each piece's coarsest step first; until a step's mesh is ready the piece
## draws nothing at that distance.
var shared := false
## A shared piece's detail steps, [[until (metres from the camera), voxel size], ...], each
## drawn from where the one before ends and fading into the next over `lod_fade` metres;
## empty draws one mesh at the parameters' own voxel size at any distance.
var lods: Array = []
var lod_fade := 0.0

## Shared meshes by generator, parameters and voxel size: {generator, params, mesh (once
## built)}.
static var _shared: Dictionary[String, Dictionary] = {}
## The frame a shared mesh was last built in.
static var _built_frame := -1
## This piece's steps still waiting for their mesh: {key, params, name, begin, until}.
var _waiting: Array[Dictionary] = []

var _body := RID()
var _shapes: Array[RID] = []
var _visual := DisplayServer.get_name() != "headless"


func _ready() -> void:
	set_process(false)
	var gen := VoxCatalog.by_name(generator)
	if gen == null:
		return
	var own_boxes := gen.has_method(&"collision")
	# A server with the boxes listed has no use for the voxels.
	var built: VoxelModel = gen.build(params) if (_visual and not shared) or not own_boxes else null
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
	if _visual and shared:
		_show_shared(gen)
	elif _visual and built != null:
		model = built
		model.set_clear_materials(PackedInt32Array([glass]))
		var mesh := VoxelChunkedMesh.new()
		mesh.name = "Mesh"
		mesh.layered = true
		mesh.model = model
		add_child(mesh)
		mesh.refresh()


func _show_shared(gen: VoxGenerator) -> void:
	var steps: Array = lods if not lods.is_empty() else [[0.0, float(params.get("voxel", 0.0))]]
	var begin := 0.0
	for i in steps.size():
		var step: Array = steps[i]
		var p := params.duplicate()
		if float(step[1]) > 0.0:
			p["voxel"] = float(step[1])
		var key := "%s %s" % [generator, JSON.stringify(p, "", true)]
		_waiting.push_front({"key": key, "params": p, "name": "Mesh%d" % i, "begin": begin, "until": float(step[0])})
		begin = float(step[0])
	# The far step first: it is the cheapest to build, and seen from the furthest.
	for w in _waiting:
		_request(str(w["key"]), gen, w["params"])
	_show_ready()
	set_process(not _waiting.is_empty())


func _process(_delta: float) -> void:
	_show_ready()
	if _waiting.is_empty():
		set_process(false)


## Adds a mesh instance for each waiting step whose mesh is ready.
func _show_ready() -> void:
	for w in _waiting.duplicate():
		var mesh := _ready_mesh(str(w["key"]))
		if mesh == null:
			continue
		_waiting.erase(w)
		var inst := MeshInstance3D.new()
		inst.name = str(w["name"])
		inst.mesh = mesh
		inst.visibility_range_begin = float(w["begin"])
		inst.visibility_range_end = float(w["until"])
		inst.visibility_range_begin_margin = lod_fade if float(w["begin"]) > 0.0 else 0.0
		inst.visibility_range_end_margin = lod_fade if float(w["until"]) > 0.0 else 0.0
		inst.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(inst)


static func _request(key: String, gen: VoxGenerator, p: Dictionary) -> void:
	if not _shared.has(key):
		_shared[key] = {"generator": gen, "params": p}


## The mesh for `key` once built; builds it now if no shared mesh was built this frame.
static func _ready_mesh(key: String) -> ArrayMesh:
	var entry: Dictionary = _shared.get(key, {})
	if entry.is_empty():
		return null
	if entry.has("mesh"):
		return entry["mesh"]
	var frame := Engine.get_process_frames()
	if frame == _built_frame:
		return null
	_built_frame = frame
	var t := Prof.start()
	var mesh := VoxGenerator.to_mesh((entry["generator"] as VoxGenerator).build(entry["params"]))
	Prof.stop(&"voxkit/shared_mesh", t)
	entry["mesh"] = mesh
	return mesh


## Forgets every shared mesh: for whoever put shared pieces up, when the world they stood in
## goes.
static func clear_shared() -> void:
	_shared.clear()


## How many shared meshes are built or waiting to be.
static func shared_mesh_count() -> int:
	return _shared.size()


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
