class_name WaterTank
extends RefCounted
## The water in a shot tank. Each hole below the surface lets out `flow` cubic metres a
## second times the square root of the water's depth over it (water leaves a hole faster
## under more head), at most `max_holes` of them at once; the level falls by what left over
## the tank's `area`. Worked out the same on the server and every client from the holes and
## when they were made, so the level is never sent.
##
## Heights are metres above the tank's floor.

## Steps for catching up on a late join; the live game steps every frame.
const CATCH_UP_STEP := 1.0 / 60.0

var area := 8.0
var height := 2.6
var level := 2.3
var flow := 0.05
var max_holes := 24
## Cubic metres let out so far (for the puddle under it).
var poured := 0.0
## Each: {height, made} with `made` on this tank's own clock.
var holes: Array[Dictionary] = []
var clock := 0.0


func add_hole(at_height: float, made: float) -> void:
	holes.append({"height": at_height, "made": made})


## The holes that pour now: below the water, the first `max_holes` made.
func pouring() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for h in holes:
		if out.size() >= max_holes:
			break
		if float(h["height"]) < level - 0.001 and float(h["made"]) <= clock:
			out.append(h)
	return out


func advance(delta: float) -> void:
	clock += delta
	var open := pouring()
	var out := 0.0
	# In one step it never falls past the highest pouring hole: that one stops there.
	var floor_at := 0.0
	for h in open:
		out += flow * sqrt(maxf(level - float(h["height"]), 0.0)) * delta
		floor_at = maxf(floor_at, float(h["height"]))
	if out <= 0.0:
		return
	var drop := minf(out / area, level - floor_at)
	level -= drop
	poured += drop * area


## A late joiner's tank: holes given with their `age` in seconds, stepped from the oldest to
## now the same way a live tank was.
func catch_up(given: Array) -> void:
	var oldest := 0.0
	for g: Dictionary in given:
		oldest = maxf(oldest, float(g["age"]))
	for g: Dictionary in given:
		add_hole(float(g["height"]), oldest - float(g["age"]))
	var steps := int(oldest / CATCH_UP_STEP)
	for i in steps:
		advance(CATCH_UP_STEP)


## Holes with how old each is now, for someone joining.
func ages() -> Array:
	var out: Array = []
	for h in holes:
		out.append({"height": float(h["height"]), "age": clock - float(h["made"])})
	return out


## The radius of a puddle `film` metres deep holding `volume` cubic metres, no more than
## `most` metres.
static func puddle_radius(volume: float, film: float, most: float) -> float:
	if volume <= 0.0:
		return 0.0
	return minf(sqrt(volume / (PI * film)), most)
