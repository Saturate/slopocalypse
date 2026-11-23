extends Node3D
## Capture setup (#455), run with --frames 180 --sheet 6: the compass strip while the view
## turns a full circle on a plain field. Coloured posts stand where the markers are: a yellow
## post for the objective (north-east, 60 m), a pale box for a car (south, 25 m), a green hut
## for the camp (west, 40 m) and a blue figure for a partner, "Ana" (north-west, 18 m). Each
## marker should slide along the strip in step with its post and stick to an edge, pointing
## out, while its post is behind. A second car right beside the camera is close enough to
## be left off.

const COLOURS := {"objective": Color("f5c542"), "car": Color("ece6d6"), "base": Color("8fc25a"), "partner": Color("5fb6ff")}
const CONFIG := "res://modules/compass/data/compass.json"

var _camera := Camera3D.new()
var _frame := 0


func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.68, 0.8)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	ground.mesh = plane
	ground.material_override = _material(Color(0.36, 0.42, 0.26))
	add_child(ground)
	_camera.position = Vector3(0, 1.7, 0)
	add_child(_camera)
	_camera.current = true
	var me := Node3D.new()
	me.add_to_group(&"players")
	_camera.add_child(me)
	_post("objective", Vector3(42, 0, -42), Vector3(1.2, 8, 1.2))
	_post("car", Vector3(0, 0, 25), Vector3(2, 1.5, 4.2))
	_post("car", Vector3(-3.0, 0, 3.5), Vector3(2, 1.5, 4.2))
	var hut := _block(Vector3(-40, 0, 0), Vector3(4, 3, 4), COLOURS["base"])
	hut.name = "Camp"
	var ana := _block(Vector3(-12.7, 0, -12.7), Vector3(0.7, 1.8, 0.7), COLOURS["partner"])
	ana.add_to_group(&"players")
	ana.set_meta(&"player_name", "Ana")
	var strip := CompassStrip.new()
	strip.config = Data.load_json(CONFIG)
	strip.player = me
	strip.set_base(Vector3(-40, 0, 0))
	add_child(strip)


func _process(_delta: float) -> void:
	_frame += 1
	# A full turn to the right over the capture, from facing north-east.
	_camera.rotation.y = -deg_to_rad(45.0 + 360.0 * float(_frame) / 180.0)


func _post(kind: String, at: Vector3, size: Vector3) -> void:
	var post := _block(at, size, COLOURS[kind])
	post.add_to_group(CompassStrip.GROUP)
	post.set_meta(CompassStrip.KIND_META, kind)


func _block(at: Vector3, size: Vector3, colour: Color) -> Node3D:
	var root := Node3D.new()
	root.position = at
	add_child(root)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position.y = size.y * 0.5
	mesh.material_override = _material(colour)
	root.add_child(mesh)
	return root


func _material(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	return m
