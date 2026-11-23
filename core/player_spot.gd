class_name PlayerSpot
extends RefCounted
## Where a player counts as being for what the server keeps going and sends around them: their
## body, or for someone in a car, the car. A seated body stays parked where it got in (the
## player module), so asking the body alone loses a driver once they drive off (#519).
##
## The cars answer through the `cars_api` group's `car_spot_of(player)`; with the car module
## off there is no such node and every player counts where their body is.


## The node answering `car_spot_of`, or null without cars. Look it up once per pass, not per
## player.
static func cars_api(tree: SceneTree) -> Node:
	return tree.get_first_node_in_group(&"cars_api")


static func of(player: Node3D, cars: Node) -> Vector3:
	var seat: Variant = cars.call(&"car_spot_of", player) if cars != null else null
	return seat if seat is Vector3 else player.global_position
