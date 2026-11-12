extends MissionType
## The test range's mission kind: no objective, nothing hostile, no clock. Its HUD lines
## name the material under the crosshair and what it takes, read from the struck voxel of
## the local copy of the building.

## How far the crosshair looks for a building, metres.
const REACH := 80.0


func server_done(_riders: Array) -> bool:
	return false


func hud_lines(player: Node3D) -> Array[String]:
	var lines: Array[String] = ["Aiming at: %s" % _aimed_at(player)]
	lines.append("G sticks a charge, T sets them off")
	return lines


## The material under the crosshair and its rules, or "nothing breakable".
func _aimed_at(player: Node3D) -> String:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return "nothing breakable"
	var from := cam.global_position
	var to := from - cam.global_basis.z * REACH
	var query := PhysicsRayQueryParameters3D.create(from, to)
	if player is CollisionObject3D:
		query.exclude = [(player as CollisionObject3D).get_rid()]
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or not hit["collider"] is MissionBuilding:
		return "nothing breakable"
	var building := hit["collider"] as MissionBuilding
	var mat := building.material_at(hit["position"], hit["normal"])
	return "%s  (%s)" % [mat, describe(VoxMaterials.named(mat))]


## A material's rules in a few words.
static func describe(m: Dictionary) -> String:
	var parts: Array[String] = ["bullets x%s" % m.get("bullet", 1.0), "blasts x%s" % m.get("blast", 1.0)]
	if float(m.get("min_bullet_damage", 0.0)) > 0.0:
		parts.append("only chips under %d damage" % int(m["min_bullet_damage"]))
	if float(m.get("pass", 0.0)) > 0.0:
		parts.append("rounds go through at x%s" % m["pass"])
	if bool(m.get("breaks_whole", false)):
		parts.append("breaks whole after %d hits" % int(m.get("hits_to_break", 1)))
	return ", ".join(parts)
