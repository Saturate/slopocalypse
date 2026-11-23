class_name GlowstickRules
extends RefCounted
## The few rules about glowsticks (#447) that need no nodes: which soldiers carry one, when
## a carrier shows it, and its colour.

const CONFIG := "res://modules/glowsticks/data/glowsticks.json"
const REQUIRED := {
	"burn_seconds": TYPE_FLOAT,
	"enemy_night_share": TYPE_FLOAT,
	"enemy_drop_seconds": TYPE_FLOAT,
	"ground_max": TYPE_FLOAT,
	"drop_ahead": TYPE_FLOAT,
	"check_seconds": TYPE_FLOAT,
	"send_seconds": TYPE_FLOAT,
	"stick": TYPE_DICTIONARY,
	"light": TYPE_DICTIONARY,
	"own_light": TYPE_DICTIONARY,
	"ground": TYPE_DICTIONARY,
	"spare_colour": TYPE_ARRAY,
}
const STICK_REQUIRED := {"size": TYPE_ARRAY, "at": TYPE_ARRAY, "glow": TYPE_FLOAT, "halo": TYPE_FLOAT, "halo_strength": TYPE_FLOAT}
const LIGHT_REQUIRED := {"energy": TYPE_FLOAT, "range": TYPE_FLOAT, "falloff": TYPE_FLOAT, "max_lights": TYPE_FLOAT}
const OWN_LIGHT_REQUIRED := {"energy": TYPE_FLOAT, "range": TYPE_FLOAT, "falloff": TYPE_FLOAT, "view_energy": TYPE_FLOAT, "view_range": TYPE_FLOAT}
const GROUND_REQUIRED := {"glow": TYPE_FLOAT, "halo": TYPE_FLOAT, "halo_strength": TYPE_FLOAT, "lift": TYPE_FLOAT, "turn": TYPE_FLOAT}
## The inventory item a fresh stick is.
const ITEM := "glowstick"


## `data` has every field the module reads, nested blocks and their sizes included.
static func valid(data: Variant) -> bool:
	if not (data is Dictionary and Data.require(CONFIG, data, REQUIRED)):
		return false
	var d: Dictionary = data
	if not (Data.require(CONFIG, d["stick"], STICK_REQUIRED) and Data.require(CONFIG, d["light"], LIGHT_REQUIRED) and Data.require(CONFIG, d["own_light"], OWN_LIGHT_REQUIRED) and Data.require(CONFIG, d["ground"], GROUND_REQUIRED)):
		return false
	if (d["stick"]["size"] as Array).size() < 2 or (d["stick"]["at"] as Array).size() < 3 or (d["spare_colour"] as Array).size() < 3:
		Log.error(&"glowsticks", "%s: stick.size needs 2 numbers, stick.at and spare_colour 3" % CONFIG)
		return false
	return true


## A soldier carries one when its spawn roll (0..1) falls inside the share.
static func soldier_carries(roll: float, share: float) -> bool:
	return roll < share


## A carrying soldier holds it up only at night and on patrol: one fighting or stalking
## someone keeps quiet, and the dead and those who gave up show nothing.
static func soldier_shows(carries: bool, night: bool, patrolling: bool) -> bool:
	return carries and night and patrolling


## The stick glows in its carrier's armband colour, so it says who they are in the dark.
static func colour_for(person: Node) -> Color:
	return Armband.colour_for(person)


static func colour(rgb: Variant) -> Color:
	var a: Array = rgb if rgb is Array else []
	if a.size() < 3:
		return Color.WHITE
	return Color(float(a[0]), float(a[1]), float(a[2]))
