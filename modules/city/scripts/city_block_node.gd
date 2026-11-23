class_name CityBlockNode
extends Node3D
## A hand-made block (CityBlock) stood on the ground: one VoxPiece per piece, put up a few a
## frame like the city's generated buildings. `vary` keys on a piece are reseeded per placement
## from `variation_seed`, so the same block looks a little different each place it stands.

var block: CityBlock
var variation_seed := 0
var builds_per_frame := 2

var _queue: Array[Dictionary] = []
var pieces: Array[VoxPiece] = []


func _ready() -> void:
	if block == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = variation_seed
	var kit := CityBlock.generators()
	for p in block.pieces:
		var params: Dictionary = (p["params"] as Dictionary).duplicate()
		var gen := kit.get(p["generator"]) as VoxGenerator
		for key: Variant in p["vary"]:
			_vary(params, str(key), gen, rng)
		_queue.append({"generator": p["generator"], "params": params, "at": p["at"], "yaw": p["yaw"]})


## A choice gets another of its options; a number another value in its range, on its step.
static func _vary(params: Dictionary, key: String, gen: VoxGenerator, rng: RandomNumberGenerator) -> void:
	for spec in gen.params():
		if spec["key"] != key:
			continue
		var lo := float(spec["min"])
		var hi := float(spec["max"])
		var step := maxf(float(spec["step"]), 0.0001)
		params[key] = lo + floorf(rng.randf() * ((hi - lo) / step + 1.0)) * step
		params[key] = minf(float(params[key]), hi)


func pending() -> int:
	return _queue.size()


func _process(_delta: float) -> void:
	if _queue.is_empty():
		return
	for i in maxi(builds_per_frame, 1):
		if _queue.is_empty():
			break
		_put_up(_queue.pop_front())


func build_all() -> void:
	while not _queue.is_empty():
		_put_up(_queue.pop_front())


func _put_up(p: Dictionary) -> void:
	var piece := VoxPiece.new()
	piece.name = "Piece%d" % pieces.size()
	piece.generator = p["generator"]
	piece.params = p["params"]
	piece.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(float(p["yaw"]))), p["at"])
	add_child(piece)
	pieces.append(piece)
