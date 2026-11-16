class_name PaneBody
extends StaticBody3D
## One intact window pane's collision, on `PhysicsLayers.GLASS`: it stops bullets and bodies
## but not sight, so soldiers see through windows. Shots that hit it are the building's:
## `MissionBuilding.of(collider)` finds it, and a round going on through asks the building.

var building: MissionBuilding
var pane := -1


func _ready() -> void:
	collision_layer = PhysicsLayers.GLASS
	collision_mask = 0
	# The building plays its own hit sounds for its panes too.
	set_meta(&"surface_sounds", true)


func bullet_exit(point: Vector3, direction: Vector3, damage: float) -> Dictionary:
	return building.bullet_exit(point, direction, damage) if is_instance_valid(building) else {}


## The chance (0..1) this pane stops one look through it: its cracks.
func sight_block_chance() -> float:
	return building.pane_sight_block(pane) if is_instance_valid(building) else 0.0
