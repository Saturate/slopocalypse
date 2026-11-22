extends Node3D
## Capture setup (#447), run with --frames 240 --sheet 6: co-op markers on a plain field in
## daylight, the camera still at eye height looking north. "Ben" (a blue figure) stands 45 m
## away behind a grey wall the whole time: his marker shows through it. "Ana" starts 70 m
## out behind a second wall, walks out from behind it and straight at the camera; her marker
## stays full while she is far, turns faint once she is in plain view within 30 m, and is
## gone when she is a couple of metres away. A red figure (an enemy) stands in the open at
## 25 m and never gets a marker.

const BLUE := Color("5fb6ff")
const RED := Color("c8402e")
const CONFIG := "res://modules/coop_marker/data/coop_marker.json"

var _camera := Camera3D.new()
var _ana: Node3D
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
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	ground.mesh = plane
	ground.material_override = _material(Color(0.36, 0.42, 0.26))
	add_child(ground)
	_camera.position = Vector3(0, 1.7, 0)
	_camera.rotation.x = deg_to_rad(-2.0)
	add_child(_camera)
	_camera.current = true
	var me := Node3D.new()
	me.add_to_group(&"players")
	me.set_meta(&"player_name", "Me")
	add_child(me)
	_wall(Vector3(-9, 0, -40), Vector3(8, 3.5, 0.6))
	var ben := _figure(Vector3(-9, 0, -45), BLUE)
	ben.add_to_group(&"players")
	ben.set_meta(&"player_name", "Ben")
	_wall(Vector3(6, 0, -64), Vector3(6, 3.5, 0.6))
	_ana = _figure(Vector3(6, 0, -70), BLUE)
	_ana.add_to_group(&"players")
	_ana.set_meta(&"player_name", "Ana")
	var enemy := _figure(Vector3(-4, 0, -25), RED)
	enemy.add_to_group(&"players")
	enemy.add_to_group(&"enemies")
	enemy.set_meta(&"team", "raiders")
	var markers := CoopMarkers.new()
	markers.config = Data.load_json(CONFIG)
	markers.player = me
	add_child(markers)


func _process(_delta: float) -> void:
	_frame += 1
	var t := clampf(float(_frame) / 230.0, 0.0, 1.0)
	# Waits behind her wall, steps out to the side of it, then comes straight in to two metres off.
	if t < 0.2:
		_ana.position = Vector3(6, 0, -70)
	elif t < 0.3:
		_ana.position = Vector3(6, 0, -70).lerp(Vector3(12, 0, -70), (t - 0.2) / 0.1)
	else:
		_ana.position = Vector3(12, 0, -70).lerp(Vector3(1.0, 0, -2.0), (t - 0.3) / 0.7)


func _wall(at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = at + Vector3.UP * size.y * 0.5
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = _material(Color(0.5, 0.5, 0.48))
	body.add_child(mesh)
	add_child(body)


func _figure(at: Vector3, colour: Color) -> Node3D:
	var root := Node3D.new()
	root.position = at
	add_child(root)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.7, 1.8, 0.5)
	mesh.mesh = box
	mesh.position.y = 0.9
	mesh.material_override = _material(colour)
	root.add_child(mesh)
	return root


func _material(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	return m
