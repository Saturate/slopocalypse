class_name PickupRules
extends RefCounted
## The numbers for items on the ground and picking them up, from `data/pickup.json` (#424):
## read once, shared by the server's checks and every client's prompt and look.

const FILE := "res://modules/inventory/data/pickup.json"
const REQUIRED := {"range": TYPE_FLOAT, "loot_reach_extra": TYPE_FLOAT, "facing": TYPE_FLOAT,
	"ground_scale": TYPE_FLOAT, "min_size": TYPE_FLOAT, "outline": TYPE_ARRAY}

static var _data: Dictionary = {}


static func number(key: String) -> float:
	return float(_rules()[key])


static func outline_colour() -> Color:
	var c: Array = _rules()["outline"]
	return Color(float(c[0]), float(c[1]), float(c[2]), float(c[3]))


static func _rules() -> Dictionary:
	if _data.is_empty():
		var data: Variant = Data.load_json(FILE)
		# A broken file is reported by Data (and fails the gate); nothing here guesses values.
		if data is Dictionary and Data.require(FILE, data, REQUIRED):
			_data = data
	return _data
