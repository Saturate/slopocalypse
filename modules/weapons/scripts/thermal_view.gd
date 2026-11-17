class_name ThermalView
extends CanvasLayer
## Client only, for a thermal scope while it is up to the eye: the view turns to dim grey
## with a grain, and warm bodies (players, soldiers, drones) within the sight's `range` show
## near white. Warm bodies get a flat marker colour as a material overlay, which the screen
## shader picks out; the overlay is depth tested, so walls and terrain still hide them.
## Publishes `weapons.thermal` when it turns on or off, so smoke can thin itself while it is.
##
## Purely what this player sees: the server decides nothing from it.

## Groups whose members are warm. Drones join `warm` themselves.
const WARM_GROUPS: Array[StringName] = [&"players", &"enemies", &"warm"]
## The overlay's colour: magenta, which nothing in the world is, so the shader can tell it
## from a bright sky.
const MARK := Color(1.0, 0.0, 1.0)
const SHADER := """
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_nearest;
uniform float grain = 0.07;
uniform float cold = 0.32;
void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	float hot = clamp((min(c.r, c.b) - c.g) * 2.5, 0.0, 1.0);
	float v = mix(l * cold, 0.95, hot);
	vec2 cell = floor(FRAGCOORD.xy / 2.0);
	float n = fract(sin(dot(cell + floor(TIME * 24.0), vec2(12.9898, 78.233))) * 43758.5453);
	v += (n - 0.5) * grain;
	COLOR = vec4(v * 0.96, v, v * 0.94, 1.0);
}
"""

## The thermal block of the optic part: `range`, `grain`, `cold`.
var settings: Dictionary = {}
## Who is looking: never marked warm in their own view.
var viewer: Node
var active := false
## Tests set where the eye is; otherwise the current camera.
var eye_override: Variant = null

var _screen: ColorRect
var _overlay: StandardMaterial3D
var _marked: Array[MeshInstance3D] = []


## The thermal settings of the optic in `slots`, or empty when it isn't thermal.
static func of_build(slots: Dictionary) -> Dictionary:
	var part: Dictionary = GunAssembly.catalogue().get(str(slots.get("optic", "")), {})
	return part.get("thermal", {})


## Warm nodes within `reach` of `eye`, leaving out `viewer`.
static func warm_in_range(nodes: Array, eye: Vector3, reach: float, viewer_node: Node) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n: Variant in nodes:
		var body := n as Node3D
		if body != null and body != viewer_node and body.is_inside_tree() and body.global_position.distance_to(eye) <= reach:
			out.append(body)
	return out


func _ready() -> void:
	layer = 4
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = SHADER
	material.shader = shader
	material.set_shader_parameter(&"grain", float(settings.get("grain", 0.07)))
	material.set_shader_parameter(&"cold", float(settings.get("cold", 0.32)))
	_screen = ColorRect.new()
	_screen.material = material
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.visible = false
	add_child(_screen)
	_overlay = StandardMaterial3D.new()
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay.albedo_color = MARK
	_overlay.disable_fog = true


func _exit_tree() -> void:
	set_active(false)


func set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	if _screen != null:
		_screen.visible = on
	if not on:
		_unmark()
	EventBus.publish(&"weapons.thermal", {"on": on})


func _process(_delta: float) -> void:
	if not active:
		return
	var t := Prof.start()
	refresh()
	Prof.stop(&"weapons/thermal", t)


## Marks the warm bodies in range now and unmarks the rest.
func refresh() -> void:
	var eye: Variant = eye_override
	if eye == null:
		var camera := get_viewport().get_camera_3d()
		if camera == null:
			return
		eye = camera.global_position
	var nodes: Array = []
	for group in WARM_GROUPS:
		nodes.append_array(get_tree().get_nodes_in_group(group))
	var meshes: Array[MeshInstance3D] = []
	for body in warm_in_range(nodes, eye, float(settings.get("range", 150.0)), viewer):
		for m in body.find_children("*", "MeshInstance3D", true, false):
			meshes.append(m as MeshInstance3D)
	for m in _marked:
		if is_instance_valid(m) and not meshes.has(m):
			m.material_overlay = null
	for m in meshes:
		m.material_overlay = _overlay
	_marked = meshes


func is_marked(mesh: MeshInstance3D) -> bool:
	return mesh.material_overlay == _overlay


func _unmark() -> void:
	for m in _marked:
		if is_instance_valid(m):
			m.material_overlay = null
	_marked.clear()
