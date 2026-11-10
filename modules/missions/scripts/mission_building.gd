class_name MissionBuilding
extends StaticBody3D
## A building in a mission zone: the voxel kit's shed (plank walls, a door, windows, a metal
## roof) with walk-in collision: the slab, four walls with a gap for the door, and the
## roof. Built the same on every instance from its layout entry (see `MissionLayout`), so
## nothing about it is sent but that entry. The door is on the local -Z side.

const DOOR_WIDTH := 1.0
const DOOR_HEIGHT := 2.0
const SLAB := 0.15
const ROOF_THICKNESS := 0.25
const WALL := 0.2
## Voxel size of the mesh: coarse enough to build quickly during a ride.
const VOXEL := 0.15

## The layout entry: `{position, yaw, width, depth, wall_height, windows, paint, seed}`.
var spec: Dictionary = {}

var _visual := DisplayServer.get_name() != "headless"


func _ready() -> void:
	add_to_group(&"mission_buildings")
	collision_layer = PhysicsLayers.SOLID
	var w := float(spec.get("width", 5.0))
	var d := float(spec.get("depth", 4.0))
	var wh := float(spec.get("wall_height", 2.8))
	for box in collision_boxes(w, d, wh):
		var shape := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = box.size
		shape.shape = b
		shape.position = box.get_center()
		add_child(shape)
	if _visual:
		var mesh := MeshInstance3D.new()
		mesh.name = "Mesh"
		mesh.mesh = VoxGenerator.to_mesh(VoxShed.new().build({
			"seed": int(spec.get("seed", 1)), "paint": int(spec.get("paint", 1)), "width": w,
			"depth": d, "wall_height": wh, "pitch": float(spec.get("pitch", 0.45)), "door": 1,
			"windows": float(spec.get("windows", 2)), "voxel": VOXEL,
		}))
		add_child(mesh)


## The solid parts, local: slab, back and side walls, the front wall on both sides of the
## door and above it, and the roof.
static func collision_boxes(w: float, d: float, wh: float) -> Array[AABB]:
	var top := minf(SLAB + DOOR_HEIGHT, wh - 0.2)
	return [
		AABB(Vector3(-w / 2.0, 0.0, -d / 2.0), Vector3(w, SLAB, d)),
		AABB(Vector3(-w / 2.0, 0.0, d / 2.0 - WALL), Vector3(w, wh, WALL)),
		AABB(Vector3(-w / 2.0, 0.0, -d / 2.0), Vector3(WALL, wh, d)),
		AABB(Vector3(w / 2.0 - WALL, 0.0, -d / 2.0), Vector3(WALL, wh, d)),
		AABB(Vector3(-w / 2.0, 0.0, -d / 2.0), Vector3(w / 2.0 - DOOR_WIDTH / 2.0, wh, WALL)),
		AABB(Vector3(DOOR_WIDTH / 2.0, 0.0, -d / 2.0), Vector3(w / 2.0 - DOOR_WIDTH / 2.0, wh, WALL)),
		AABB(Vector3(-DOOR_WIDTH / 2.0, top, -d / 2.0), Vector3(DOOR_WIDTH, wh - top, WALL)),
		AABB(Vector3(-w / 2.0, wh, -d / 2.0), Vector3(w, ROOF_THICKNESS, d)),
	]


## A spot on the floor inside, `along` (0..1 from the door to the back wall) and `side`
## (-1..1 across), in world space.
func inside(along: float, side: float) -> Vector3:
	var w := float(spec.get("width", 5.0))
	var d := float(spec.get("depth", 4.0))
	var local := Vector3(side * (w / 2.0 - WALL - 0.6), SLAB, lerpf(-d / 2.0 + WALL + 0.6, d / 2.0 - WALL - 0.6, along))
	return global_transform * local


## Where guards can stand, in world space, as `[{at, yaw}]` (yaw as a player's: facing
## -Z turned by it): a sentry outside the door looking out, and two inside at the back
## watching the door.
func posts() -> Array:
	var d := float(spec.get("depth", 4.0))
	var door_out := global_transform * Vector3(0.6, SLAB, -d / 2.0 - 1.4)
	# The door is on local -Z, so facing local -Z is both "watching the door" from inside and
	# "looking out" from in front of it.
	var facing := global_rotation.y
	return [
		{"at": door_out, "yaw": facing},
		{"at": inside(0.9, -0.6), "yaw": facing},
		{"at": inside(0.9, 0.6), "yaw": facing},
	]
