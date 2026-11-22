extends Node
## Co-op partner markers (#447): client only, for the local player. A small blue marker over
## each other player with their name and distance, through walls within a range, fading out
## up close and when they are plainly in view (CoopMarkerRules). Names come with each
## player's spawn (the `player_name` meta) and who sits in which car from `car.entered`;
## nothing new is sent.

const CONFIG := "res://modules/coop_marker/data/coop_marker.json"

var config: Dictionary = {}

var _markers: CoopMarkers
## Player instance id -> the car they sit in; shared with the markers.
var _rides: Dictionary = {}


func _ready() -> void:
	var data: Variant = Data.load_json(CONFIG)
	if not (data is Dictionary and Data.require(CONFIG, data, CoopMarkerRules.REQUIRED)):
		return
	config = data
	EventBus.subscribe(&"player.spawned", _on_player_spawned)
	EventBus.subscribe(&"car.entered", _on_car_entered)
	EventBus.subscribe(&"car.exited", _on_car_exited)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"player.spawned", _on_player_spawned)
	EventBus.unsubscribe(&"car.entered", _on_car_entered)
	EventBus.unsubscribe(&"car.exited", _on_car_exited)


## Client: the partner markers as last drawn ({name, distance, in_sight, alpha, shown, ahead,
## at}, see CoopMarkers.items), empty before the local player spawns. Read by tools.
func markers() -> Array[Dictionary]:
	return _markers.drawn() if _markers != null else [] as Array[Dictionary]


func _on_car_entered(payload: Dictionary) -> void:
	var who := payload.get("player") as Node
	var car := payload.get("car") as Node3D
	if who != null and car != null:
		_rides[who.get_instance_id()] = car


func _on_car_exited(payload: Dictionary) -> void:
	var who := payload.get("player") as Node
	if who != null:
		_rides.erase(who.get_instance_id())


func _on_player_spawned(payload: Dictionary) -> void:
	# A server (or any headless run) draws nothing.
	if not bool(payload.get("local", false)) or DisplayServer.get_name() == "headless":
		return
	var player := payload.get("player") as Node3D
	if player == null:
		return
	if _markers == null:
		_markers = CoopMarkers.new()
		_markers.name = "Markers"
		_markers.config = config
		_markers.rides = _rides
		add_child(_markers)
	_markers.player = player
