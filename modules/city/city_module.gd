extends Node
## The city, first steps (#220, #331): apartment blocks beside the road that you can walk
## into and fight through (CityBuilding), on levelled ground. Placed the same on the server
## and every client from data and the road, so nothing about them is sent.

const CONFIG := "res://modules/city/data/city.json"
const REQUIRED := {"buildings": TYPE_ARRAY, "pad_margin": TYPE_FLOAT, "pad_blend": TYPE_FLOAT}

var config: Dictionary = {}
var buildings: Array[CityBuilding] = []


func _ready() -> void:
	var data: Variant = Data.load_json(CONFIG)
	if not (data is Dictionary and Data.require(CONFIG, data, REQUIRED)):
		return
	config = data
	EventBus.subscribe(&"world.ready", _on_world_ready)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"world.ready", _on_world_ready)


func _on_world_ready(_p: Dictionary) -> void:
	if not buildings.is_empty():
		return
	var ground := get_tree().get_first_node_in_group(&"ground")
	if ground == null or not ground.has_method(&"road_point"):
		return
	var spots: Array[Transform3D] = []
	for b: Dictionary in config["buildings"]:
		var m := float(b["at"])
		var centre: Vector3 = ground.call(&"road_point", m)
		var along: Vector3 = (ground.call(&"road_point", m + 1.0) as Vector3) - centre
		along.y = 0.0
		var right := along.normalized().cross(Vector3.UP) if along.length() > 0.001 else Vector3.RIGHT
		var at := centre + right * float(b["side"])
		var toward := (centre - at)
		toward.y = 0.0
		var spot := Transform3D(Basis.looking_at(toward.normalized()), at)
		spot.origin.y = _pad_height(ground, spot, b)
		spots.append(spot)
	place(spots)
	if ground.has_method(&"set_pads_for"):
		var pads: Array = []
		for building in buildings:
			var plan := building.plan()
			var margin := float(config["pad_margin"])
			pads.append({
				"at": building.global_position,
				"half": Vector2(float(plan["length"]) / 2.0 + margin, float(plan["depth"]) / 2.0 + margin),
				"yaw": building.global_rotation.y,
				"blend": float(config["pad_blend"]),
			})
		ground.call(&"set_pads_for", &"city", pads)


## The ground under a footprint: the middle of its corners and centre, so it sits neither
## buried nor on stilts.
func _pad_height(ground: Node, spot: Transform3D, b: Dictionary) -> float:
	var plan := VoxApartment.new().layout(b)
	var hx := float(plan["length"]) / 2.0
	var hz := float(plan["depth"]) / 2.0
	var heights: Array[float] = []
	for c: Vector3 in [Vector3.ZERO, Vector3(hx, 0, hz), Vector3(-hx, 0, hz), Vector3(hx, 0, -hz), Vector3(-hx, 0, -hz)]:
		var p := spot * c
		heights.append(float(ground.call(&"ground_height", p.x, p.z)))
	heights.sort()
	return heights[heights.size() / 2]


## Everywhere: a building at each spot with the data's parameters, in order.
func place(spots: Array[Transform3D]) -> void:
	var list: Array = config["buildings"]
	for i in spots.size():
		var building := CityBuilding.new()
		building.name = "Building%d" % buildings.size()
		building.params = list[i] if i < list.size() else {}
		building.transform = spots[i]
		add_child(building)
		buildings.append(building)
