extends Node
## The compass strip along the top of the screen (#455): client only, for the local player.
## The strip (CompassStrip) finds what to show by itself; this gives it the base (the camp's
## centre, from the camp layout in `world.ready`) and the player. Other modules add markers by putting a Node3D in the
## `compass_markers` group with a `compass_kind` meta; nothing here knows them.

const CONFIG := "res://modules/compass/data/compass.json"
const REQUIRED := {"span_degrees": TYPE_FLOAT, "tick_degrees": TYPE_FLOAT, "width_share": TYPE_FLOAT, "height": TYPE_FLOAT,
	"top_margin": TYPE_FLOAT, "marker_size": TYPE_FLOAT, "fade_near_m": TYPE_FLOAT, "fade_band_m": TYPE_FLOAT,
	"crowd_share": TYPE_FLOAT, "opacity": TYPE_FLOAT, "colours": TYPE_DICTIONARY}

var config: Dictionary = {}

var _strip: CompassStrip
var _base := Vector3.ZERO
var _has_base := false


func _ready() -> void:
	var data: Variant = Data.load_json(CONFIG)
	if not (data is Dictionary and Data.require(CONFIG, data, REQUIRED)):
		return
	config = data
	EventBus.subscribe(&"world.ready", _on_world_ready)
	EventBus.subscribe(&"player.spawned", _on_player_spawned)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"world.ready", _on_world_ready)
	EventBus.unsubscribe(&"player.spawned", _on_player_spawned)


func _on_world_ready(payload: Dictionary) -> void:
	var camp := CampLayout.of_ready(payload)
	if camp == null:
		return
	_base = camp.centre
	_has_base = true
	if _strip != null:
		_strip.set_base(_base)


func _on_player_spawned(payload: Dictionary) -> void:
	# A server (or any headless run) draws nothing.
	if not bool(payload.get("local", false)) or DisplayServer.get_name() == "headless":
		return
	var player := payload.get("player") as Node3D
	if player == null:
		return
	if _strip == null:
		_strip = CompassStrip.new()
		_strip.name = "Compass"
		_strip.config = config
		if _has_base:
			_strip.set_base(_base)
		add_child(_strip)
	_strip.player = player
