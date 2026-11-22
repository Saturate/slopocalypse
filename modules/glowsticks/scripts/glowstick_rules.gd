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
	"check_seconds": TYPE_FLOAT,
	"send_seconds": TYPE_FLOAT,
	"stick": TYPE_DICTIONARY,
	"light": TYPE_DICTIONARY,
	"spare_colour": TYPE_ARRAY,
}
## The inventory item a fresh stick is.
const ITEM := "glowstick"


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
