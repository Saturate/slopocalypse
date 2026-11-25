extends Node
## The harbour by the players' camp on an island (#454): the jetty out to the map's harbour
## spot and a boat shed, crates, nets, a fuel tank and a moored boat beside it (HarbourPlan),
## as voxel kit pieces. The spot comes with `world.ready` (MapShape.harbour); every machine
## builds the same from the map, so nothing is sent, and the server gets the same collision
## as its clients. The boat is scenery until trips by boat come (#454 part 2). Not saved;
## nothing on a map without a coast.

var config: Dictionary = {}
var pieces: Array[VoxPiece] = []
var _built := false


func _ready() -> void:
	var data: Variant = Data.load_json(HarbourPlan.CONFIG)
	if not (data is Dictionary and Data.require(HarbourPlan.CONFIG, data, HarbourPlan.REQUIRED)):
		return
	var problems := HarbourPlan.check(data)
	for problem in problems:
		Log.error(&"harbour", "%s: %s" % [HarbourPlan.CONFIG, problem])
	if not problems.is_empty():
		return
	config = data
	EventBus.subscribe(&"world.ready", _on_world_ready)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"world.ready", _on_world_ready)


func _on_world_ready(p: Dictionary) -> void:
	var harbour: Dictionary = p.get("harbour", {})
	if _built or config.is_empty() or harbour.is_empty():
		return
	var ground := get_tree().get_first_node_in_group(&"ground")
	if ground == null or not ground.has_method(&"ground_height"):
		return
	_built = true
	var height := Callable(ground, &"ground_height")
	# A jetty whose deck the shore never comes up to could not be walked onto: none at all.
	if not bool(HarbourPlan.jetty_line(harbour, height, config)["landed"]):
		Log.warn(&"harbour", "the shore at the harbour never comes up to the jetty's deck; no harbour built")
		return
	var t := Prof.start()
	for piece: Dictionary in HarbourPlan.plan(harbour, height, config):
		_put_up(piece)
	Prof.stop(&"harbour/build", t)


func _put_up(p: Dictionary) -> void:
	var piece := VoxPiece.new()
	piece.name = "%s%d" % [str(p["kind"]).to_pascal_case(), pieces.size()]
	piece.generator = p["generator"]
	piece.params = p["params"]
	piece.transform = p["transform"]
	piece.set_meta(&"harbour_piece", p["kind"])
	add_child(piece)
	pieces.append(piece)
