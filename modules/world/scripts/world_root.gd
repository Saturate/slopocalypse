class_name WorldRoot
extends Node3D
## The world scene's root: once the ground is up, lays out the players' camp on the map's
## camp pad (CampLayout), puts the spawn on its respawn spot and the car on its car spot nose
## to the gate, and fits the boundary walls round the map. In the scene rather than the world
## module so a world built on its own (a test, a capture) stands the same as a played one.

## Metres the map's boundary walls reach past its lowest and highest ground, so nothing
## slips under or over them.
const WALL_MARGIN := 100.0

@export_file("*.json") var config_path: String = "res://modules/world/data/world.json"

## The camp laid out on this map; null off the map.
var camp: CampLayout

## Whether this root picked the default map itself (nobody had selected one): it clears the
## selection again on the way out, so the next world built in the same process starts clean.
var _picked_default := false


func _ready() -> void:
	var data: Variant = Data.load_json(config_path)
	if not data is Dictionary or not (data as Dictionary).get("camp") is Dictionary:
		return
	var problem := CampLayout.check(data["camp"])
	if not problem.is_empty():
		Log.error(&"world", "%s camp: %s" % [config_path, problem])
		return
	_picked_default = not WorldMaps.is_selected()
	var map := WorldMaps.shape_or_default()
	if map != null:
		place_on_map(map, data["camp"])


## Lays out the camp on the map's camp pad, puts the spawn a metre over its respawn spot and
## the car on its car spot, and fits the boundary walls to the map.
func place_on_map(map: MapShape, camp_cfg: Dictionary) -> void:
	var pad := map.camp_pad()
	if pad.is_empty():
		var at := map.camp()
		camp = CampLayout.around(at, map.forward(), camp_cfg)
	else:
		camp = CampLayout.make(pad["centre"], pad["out"], pad["footprint"], camp_cfg)
		# The fence must stand on the levelled pad, a metre in from its edge.
		var need := (camp.half + 1.0) * 2.0
		if (pad["footprint"] as Rect2).size.x < need:
			Log.error(&"world", "the map's camp pad is %.0f m a side; world.json camp.fence needs %.0f (settlements.camp.size in the recipe)" % [(pad["footprint"] as Rect2).size.x, need])
	var spawn := get_node_or_null("SpawnPoint") as Node3D
	if spawn != null:
		spawn.position = camp.spot("respawn").origin + Vector3.UP
	var car := get_node_or_null("CarSpawn") as Node3D
	if car != null:
		var at := camp.spot("car")
		at.origin.y = map.height_at(at.origin.x, at.origin.z) + 1.0
		car.transform = at
	var boundary := get_node_or_null("Boundary")
	if boundary == null:
		return
	var area := map.extent()
	var mid_y := (map.low() + map.high()) / 2.0
	var height := map.high() - map.low() + WALL_MARGIN * 2.0
	var walls := {"North": [Vector3(area.get_center().x, mid_y, area.position.y + 1.0), Vector3(area.size.x, height, 2.0)],
		"South": [Vector3(area.get_center().x, mid_y, area.end.y - 1.0), Vector3(area.size.x, height, 2.0)],
		"West": [Vector3(area.position.x + 1.0, mid_y, area.get_center().y), Vector3(2.0, height, area.size.y)],
		"East": [Vector3(area.end.x - 1.0, mid_y, area.get_center().y), Vector3(2.0, height, area.size.y)]}
	for wall: String in walls:
		var shape := boundary.get_node_or_null(wall) as CollisionShape3D
		if shape == null:
			continue
		var box := BoxShape3D.new()
		box.size = walls[wall][1]
		shape.shape = box
		shape.position = walls[wall][0]


func _exit_tree() -> void:
	if _picked_default:
		WorldMaps.clear()
