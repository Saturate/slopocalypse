class_name FlatGround
extends StaticBody3D
## The flat test world's ground (`--world=flat`): a plain level plane, `size` metres across, at
## height 0, with nothing streamed in. Answers what other modules ask of the ground the way the
## voxel terrain does: heights are 0 everywhere, the road runs straight along -Z from the
## spawn, levelling pads change nothing, and it is ready from the start.

signal dug(center: Vector3, radius: float)

## Side of the plane, metres.
@export var size := 1200.0


func _ready() -> void:
	add_to_group(&"ground")
	collision_layer = PhysicsLayers.SOLID


func ground_height(_x: float, _z: float) -> float:
	return 0.0


func surface_height(_x: float, _z: float) -> float:
	return 0.0


## A point `metres` down the straight road from the spawn.
func road_point(metres: float) -> Vector3:
	return Vector3(0.0, 0.0, -metres)


func is_ready_at(_point: Vector3, _radius: float = 8.0) -> bool:
	return true


## Already level everywhere.
func set_pads(_pads: Array) -> void:
	pass


## Blasts leave the plane as it is (no craters in the test world).
func server_dig(_at: Vector3, _radius: float) -> void:
	pass
