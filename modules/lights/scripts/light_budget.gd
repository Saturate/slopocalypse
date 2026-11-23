class_name LightBudget
extends Node
## Client: keeps the number of real lights on screen fixed however many lamps there are. Of
## the lights in the `light_points` group, the `max_shadow` nearest the camera cast shadows,
## the next `max_lit` light without them, and the rest are off (a lamp's bulb still glows).
## A light fades over `fade` seconds as it crosses one of those lines, so it doesn't pop.
##
## Other modules only add their steady lights to the group; flashes and blinkers that set
## their own energy stay out of it.

const GROUP := &"light_points"
const OFF := 0
const LIT := 1
const SHADOW := 2

var max_shadow := 4
var max_lit := 16
var fade := 0.3
## Tests set where the eye is; otherwise the current camera.
var eye_override: Variant = null

## Light instance id -> how far faded in, 0..1. By id, so a light that was freed (a bulb shot
## out) simply drops out at the next step.
var _weight: Dictionary[int, float] = {}


## For each distance, OFF, LIT or SHADOW by how near it is among them.
static func ranks(distances: Array[float], shadow_n: int, lit_n: int) -> Array[int]:
	var order: Array[int] = []
	for i in distances.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return distances[a] < distances[b])
	var out: Array[int] = []
	out.resize(distances.size())
	for place in order.size():
		out[order[place]] = SHADOW if place < shadow_n else (LIT if place < shadow_n + lit_n else OFF)
	return out


func _process(delta: float) -> void:
	var t := Prof.start()
	step(delta)
	Prof.stop(&"lights/budget", t)


func step(delta: float) -> void:
	var eye: Variant = eye_override
	if eye == null:
		var camera := get_viewport().get_camera_3d()
		if camera == null:
			return
		eye = camera.global_position
	var lights: Array[Light3D] = []
	var distances: Array[float] = []
	for node: Node in get_tree().get_nodes_in_group(GROUP):
		var light := node as Light3D
		if light == null or not light.is_inside_tree():
			continue
		if not light.has_meta(&"full_energy"):
			# What the light was made with: the budget only ever scales it down.
			light.set_meta(&"full_energy", light.light_energy)
			light.set_meta(&"casts_shadow", light.shadow_enabled)
		lights.append(light)
		distances.append(light.global_position.distance_squared_to(eye))
	var rank := ranks(distances, max_shadow, max_lit)
	var rate := delta / maxf(fade, 0.001)
	var next: Dictionary[int, float] = {}
	for i in lights.size():
		var light := lights[i]
		var w := move_toward(_weight.get(light.get_instance_id(), 0.0), 0.0 if rank[i] == OFF else 1.0, rate)
		next[light.get_instance_id()] = w
		light.light_energy = float(light.get_meta(&"full_energy")) * w
		light.visible = w > 0.0
		light.shadow_enabled = rank[i] == SHADOW and bool(light.get_meta(&"casts_shadow"))
	_weight = next
