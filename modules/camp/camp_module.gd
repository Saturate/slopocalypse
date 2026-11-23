extends Node
## The players' camp (#420): the wooden fence round it with its gate where the highway
## leaves, the walk-in hut and the packed-dirt yards, built from the camp the world lays out
## on its pad (CampLayout, carried by `world.ready`) as voxel kit pieces (CampPlan). Where
## the board, the trader, the transport, the car and the respawn stand is the world's layout
## too, so the rest of the game finds them with this module off. Every machine builds the
## same from the map, so nothing is sent; the pieces start standing and are not saved. The
## flat test world gets no fence.

var config: Dictionary = {}
var pieces: Array[VoxPiece] = []
## The camp this world got; null until the world is ready.
var camp: CampLayout


func _ready() -> void:
	var data: Variant = Data.load_json(CampPlan.CONFIG)
	if not (data is Dictionary and Data.require(CampPlan.CONFIG, data, CampPlan.REQUIRED)):
		return
	config = data
	EventBus.subscribe(&"world.ready", _on_world_ready)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"world.ready", _on_world_ready)


func _on_world_ready(p: Dictionary) -> void:
	if camp != null or config.is_empty():
		return
	var ground := get_tree().get_first_node_in_group(&"ground")
	if ground == null or not ground.has_method(&"on_map") or not bool(ground.call(&"on_map")):
		return
	camp = CampLayout.of_ready(p)
	if camp == null:
		return
	var t := Prof.start()
	for piece: Dictionary in CampPlan.plan(camp, config):
		_put_up(piece)
	var scenery := get_tree().get_first_node_in_group(&"scenery")
	if scenery != null and scenery.has_method(&"set_yards_for"):
		scenery.call(&"set_yards_for", &"camp", CampPlan.yards(camp, config))
	Prof.stop(&"camp/build", t)


func _put_up(p: Dictionary) -> void:
	var piece := VoxPiece.new()
	piece.name = "%s%d" % [str(p["kind"]).to_pascal_case(), pieces.size()]
	piece.generator = p["generator"]
	piece.params = p["params"]
	piece.transform = p["transform"]
	piece.set_meta(&"camp_piece", p["kind"])
	add_child(piece)
	pieces.append(piece)
