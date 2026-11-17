extends Node
## The city (#333, #220, part of #331): a European city of perimeter blocks beside the road
## (CitySite), on levelled ground cleared of trees, that you can walk into and fight through.
## Placed the same on the server and every client from data and the road, so nothing about
## it is sent.

const CONFIG := "res://modules/city/data/city.json"
const REQUIRED := {
	"seed": TYPE_FLOAT, "at": TYPE_FLOAT, "side": TYPE_FLOAT, "size": TYPE_FLOAT, "blocks": TYPE_FLOAT,
	"street_width": TYPE_FLOAT, "street_jitter": TYPE_FLOAT, "pavement": TYPE_FLOAT, "passage_width": TYPE_FLOAT,
	"building_depth": TYPE_FLOAT, "floors_edge": TYPE_FLOAT, "floors_middle": TYPE_FLOAT, "style": TYPE_STRING,
	"pad_blend": TYPE_FLOAT, "builds_per_frame": TYPE_FLOAT,
}
## Clearing circles over the footprint are this far apart.
const CLEARING_STEP := 20.0

var config: Dictionary = {}
var site: CitySite


func _ready() -> void:
	var data: Variant = Data.load_json(CONFIG)
	if not (data is Dictionary and Data.require(CONFIG, data, REQUIRED)):
		return
	config = data
	EventBus.subscribe(&"world.ready", _on_world_ready)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"world.ready", _on_world_ready)


func _on_world_ready(_p: Dictionary) -> void:
	if site != null:
		return
	var ground := get_tree().get_first_node_in_group(&"ground")
	if ground == null or not ground.has_method(&"road_point"):
		return
	place(spot(ground, config))
	var size := float(config["size"])
	if ground.has_method(&"set_pads_for"):
		ground.call(&"set_pads_for", &"city", [{"at": site.global_position, "half": Vector2(size / 2.0, size / 2.0), "yaw": site.global_rotation.y, "blend": float(config["pad_blend"])}])
	var scenery := get_tree().get_first_node_in_group(&"scenery")
	if scenery != null and scenery.has_method(&"set_clearings_for"):
		scenery.call(&"set_clearings_for", &"city", clearings(site.global_transform, size))


## Where the city stands: beside the road `at` metres out, its near edge `side` metres from
## the road's middle, squared to the road there and level at the ground's middle height.
static func spot(ground: Node, cfg: Dictionary) -> Transform3D:
	var m := float(cfg["at"])
	var centre: Vector3 = ground.call(&"road_point", m)
	var along: Vector3 = (ground.call(&"road_point", m + 1.0) as Vector3) - centre
	along.y = 0.0
	along = along.normalized() if along.length() > 0.001 else Vector3.FORWARD
	var right := along.cross(Vector3.UP)
	var side := float(cfg["side"])
	var size := float(cfg["size"])
	var away := right * signf(side) if side != 0.0 else right
	var at := centre + away * (absf(side) + size / 2.0)
	# -z toward the road.
	var basis := Basis.looking_at(-away)
	var heights: Array[float] = []
	for c: Vector3 in [Vector3.ZERO, Vector3(size / 2.0, 0, size / 2.0), Vector3(-size / 2.0, 0, size / 2.0), Vector3(size / 2.0, 0, -size / 2.0), Vector3(-size / 2.0, 0, -size / 2.0)]:
		var p := at + basis * c
		heights.append(float(ground.call(&"ground_height", p.x, p.z)))
	heights.sort()
	at.y = heights[heights.size() / 2]
	return Transform3D(basis, at)


## Circles covering the square footprint, so nothing grows in the city.
static func clearings(where: Transform3D, size: float) -> Array:
	var out: Array = []
	var steps := ceili(size / CLEARING_STEP)
	for i in steps + 1:
		for j in steps + 1:
			var local := Vector3(-size / 2.0 + i * size / steps, 0.0, -size / 2.0 + j * size / steps)
			out.append({"at": where * local, "radius": CLEARING_STEP * 0.75})
	return out


## Everywhere: the city at `where`.
func place(where: Transform3D) -> void:
	site = CitySite.new()
	site.name = "City"
	site.config = config
	site.transform = where
	add_child(site)
