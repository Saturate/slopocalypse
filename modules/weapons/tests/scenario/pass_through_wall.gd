extends StaticBody3D
## A stand-in wall for the pass-through tests: lets a round on through, 0.5 m on, at
## `scale` of its damage, or stops it (`stops`). Counts the rounds that asked.

var scale_left := 0.6
var stops := false
var asked := 0


func bullet_exit(point: Vector3, direction: Vector3, _damage: float) -> Dictionary:
	asked += 1
	if stops:
		return {}
	return {"exit": point + direction.normalized() * 0.5, "scale": scale_left}
