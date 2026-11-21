class_name WorldRoot
extends Node3D
## The world scene's root: once the ground is up, puts the spawn at the map's camp, the car
## beside it facing down the highway, and the boundary walls round the map. In the scene
## rather than the world module so a world built on its own (a test, a capture) stands the
## same as a played one.

## Metres the map's boundary walls reach past its lowest and highest ground, so nothing
## slips under or over them.
const WALL_MARGIN := 100.0
const REQUIRED := {"car_ahead": TYPE_FLOAT, "car_side": TYPE_FLOAT}

@export_file("*.json") var config_path: String = "res://modules/world/data/world.json"

## Whether this root picked the default map itself (nobody had selected one): it clears the
## selection again on the way out, so the next world built in the same process starts clean.
var _picked_default := false


func _ready() -> void:
	var data: Variant = Data.load_json(config_path)
	if not data is Dictionary or not (data as Dictionary).get("map") is Dictionary:
		return
	if not Data.require(config_path + " map", data["map"], REQUIRED):
		return
	_picked_default = not WorldMaps.is_selected()
	var map := WorldMaps.shape_or_default()
	if map != null:
		place_on_map(map, data["map"])


## Puts the spawn at the map's camp and the car `car_ahead` metres toward the highway and
## `car_side` to its right, nose down the highway, and fits the boundary walls to the map.
func place_on_map(map: MapShape, cfg: Dictionary) -> void:
	var camp := map.camp()
	var forward := map.forward()
	var spawn := get_node_or_null("SpawnPoint") as Node3D
	if spawn != null:
		spawn.position = camp + Vector3.UP
	var car := get_node_or_null("CarSpawn") as Node3D
	if car != null:
		var side := forward.cross(Vector3.UP).normalized()
		var at := camp + forward * float(cfg["car_ahead"]) + side * float(cfg["car_side"])
		at.y = map.height_at(at.x, at.z) + 1.0
		# Cars drive along their +Z: the nose points down the highway.
		car.transform = Transform3D(Basis.looking_at(-forward, Vector3.UP), at)
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
