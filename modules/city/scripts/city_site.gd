class_name CitySite
extends Node3D
## A city on the ground (CityLayout): levelled, cleared of trees and grass, its streets laid
## in asphalt, pavements a kerb high round every block and over the square, and its apartment
## blocks (CityBuilding) put up a few a frame so loading it doesn't stall. Built the same on
## the server and every client from the layout's seed.
##
## Origin at the city's middle, on its level ground; -z toward the road it joins.

const KERB := 0.15
const PAVEMENT_COLOUR := Color(0.6, 0.59, 0.56)
const SQUARE_COLOUR := Color(0.55, 0.52, 0.48)

## city.json.
var config: Dictionary = {}
var plan: Dictionary = {}
var buildings: Array[CityBuilding] = []

var _queue: Array[Dictionary] = []
var _body := RID()
var _shapes: Array[RID] = []
var _visual := DisplayServer.get_name() != "headless"


func _ready() -> void:
	plan = CityLayout.make(config, int(config.get("seed", 1)))
	_body = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_collision_layer(_body, PhysicsLayers.SOLID)
	PhysicsServer3D.body_set_collision_mask(_body, 0)
	PhysicsServer3D.body_attach_object_instance_id(_body, get_instance_id())
	PhysicsServer3D.body_set_space(_body, get_world_3d().space)
	PhysicsServer3D.body_set_state(_body, PhysicsServer3D.BODY_STATE_TRANSFORM, global_transform)
	for block: Rect2 in plan["blocks"]:
		_slab(block, PAVEMENT_COLOUR if not (plan["squares"] as Array).has(block) else SQUARE_COLOUR)
	if _visual:
		for street: Rect2 in plan["streets"]:
			_street(street)
	_queue.assign(plan["buildings"])


## Buildings still to put up.
func pending() -> int:
	return _queue.size()


func _process(_delta: float) -> void:
	if _queue.is_empty():
		return
	var t := Prof.start()
	for i in maxi(int(config.get("builds_per_frame", 2)), 1):
		if _queue.is_empty():
			break
		_put_up(_queue.pop_front())
	Prof.stop(&"city/site", t)


## Everything at once (tests and tools).
func build_all() -> void:
	while not _queue.is_empty():
		_put_up(_queue.pop_front())


func _put_up(b: Dictionary) -> void:
	var foot: Rect2 = b["footprint"]
	var building := CityBuilding.new()
	building.name = "Building%d" % buildings.size()
	building.params = b["params"]
	# On the pavement's top, so the front steps meet it.
	building.transform = Transform3D(Basis(Vector3.UP, float(b["yaw"])), Vector3(foot.get_center().x, KERB, foot.get_center().y))
	add_child(building)
	buildings.append(building)


## A raised slab (a block's pavement, the square), `KERB` high: collision, and a plain mesh.
func _slab(rect: Rect2, colour: Color) -> void:
	var size := Vector3(rect.size.x, KERB, rect.size.y)
	var centre := Vector3(rect.get_center().x, KERB / 2.0, rect.get_center().y)
	var shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(shape, size / 2.0)
	PhysicsServer3D.body_add_shape(_body, shape, Transform3D(Basis.IDENTITY, centre))
	_shapes.append(shape)
	if not _visual:
		return
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.95
	box.material = material
	mesh.mesh = box
	mesh.position = centre
	add_child(mesh)


## Asphalt with lane markings along the street, in voxel road pieces (VoxRoad), sunk so its
## surface sits on the level ground. Two lanes fill the street kerb to kerb.
func _street(rect: Rect2) -> void:
	var along_x := rect.size.x > rect.size.y
	var length := maxf(rect.size.x, rect.size.y)
	var width := minf(rect.size.x, rect.size.y)
	var pieces := ceili(length / 50.0)
	var each := length / pieces
	for i in pieces:
		var model := VoxRoad.new().build({"seed": i + 7, "length": each, "lanes": 2.0, "lane_width": width / 2.0, "shoulder": 0.0, "wear": 0.25, "potholes": 2.0})
		var part := MeshInstance3D.new()
		part.mesh = VoxRoad.new().to_mesh(model)
		var start := (rect.position.x if along_x else rect.position.y) + each * (i + 0.5)
		var at := Vector3(start, -VoxRoad.BED, rect.get_center().y) if along_x else Vector3(rect.get_center().x, -VoxRoad.BED, start)
		part.transform = Transform3D(Basis(Vector3.UP, PI / 2.0) if along_x else Basis.IDENTITY, at)
		add_child(part)


func _exit_tree() -> void:
	if _body.is_valid():
		PhysicsServer3D.free_rid(_body)
		_body = RID()
	for shape in _shapes:
		PhysicsServer3D.free_rid(shape)
	_shapes.clear()
