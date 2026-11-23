extends Node
## Smoke from blasts and crashes: plumes that drift with the wind and hide soldiers' targets.
## The server tracks them (SmokeField); windowed clients draw them (SmokeView).

const CONFIG := "res://modules/smoke/data/smoke.json"
const REQUIRED := {
	"wind": TYPE_ARRAY, "rise_speed": TYPE_FLOAT, "max_volumes": TYPE_FLOAT, "sight_block": TYPE_FLOAT,
	"fog_radius": TYPE_FLOAT, "fog_density": TYPE_FLOAT, "fog_albedo": TYPE_ARRAY, "fog_ambient": TYPE_FLOAT, "colour": TYPE_ARRAY, "particles": TYPE_FLOAT, "thermal_share": TYPE_FLOAT,
	"sources": TYPE_DICTIONARY,
}

var config: Dictionary = {}


func _ready() -> void:
	var data: Variant = Data.load_json(CONFIG)
	if not (data is Dictionary and Data.require(CONFIG, data, REQUIRED)):
		return
	config = data
	var field := SmokeField.new()
	field.name = "Field"
	field.config = config
	add_child(field)
	if DisplayServer.get_name() != "headless":
		var view := SmokeView.new()
		view.name = "View"
		view.config = config
		add_child(view)
