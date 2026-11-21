extends Node3D
## Capture setup: every wire kind strung between plain posts out from the camp, the sun
## behind the camera. The camera walks in from where the far lines are thin to the barbed
## wire fence close up. Rows, near to far: barbed wire on fence posts, steel cable between
## two posts with a guy wire down to the ground, low-voltage lines on poles, high-voltage
## lines on tall towers.

const WORLD := "res://modules/world/scenes/world.tscn"
const WIRES := "res://modules/wires/wires_module.gd"
## Out from the camp, on open ground clear of it.
const OUT := Vector3(0, 0, -40)
const POST_COLOUR := Color(0.36, 0.27, 0.19)

var _world: Node
var _camera := Camera3D.new()
var _ticks := 0
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _aim := Vector3.ZERO
var _post_material := StandardMaterial3D.new()


func _ready() -> void:
	_world = await VoxelWorld.add_and_wait(self, WORLD)
	_post_material.albedo_color = POST_COLOUR
	var wires: Node = (load(WIRES) as GDScript).new()
	add_child(wires)
	wires.call(&"set_spans", "barbed", _fence(-6.0, [-9.0, -6.0, -3.0, 0.0, 3.0, 6.0, 9.0], 1.3, [0.45, 0.85, 1.25], &"barbed"))
	wires.call(&"set_spans", "cable", _cable(-16.0))
	wires.call(&"set_spans", "low", _fence(-30.0, [-40.0, -10.0, 20.0, 50.0], 8.0, [7.6, 7.2], &"low_voltage"))
	wires.call(&"set_spans", "high", _towers(-60.0, [-90.0, -10.0, 70.0]))
	_from = VoxelWorld.spawn_of(_world, OUT + Vector3(-3, 3.5, 10))
	_to = VoxelWorld.spawn_of(_world, OUT + Vector3(-1, 1.6, -3.5))
	_aim = VoxelWorld.spawn_of(_world, OUT + Vector3(0, 4, -40))
	add_child(_camera)
	_camera.current = true
	_camera.fov = 65.0
	_camera.far = 800.0
	_place_camera(0.0)
	# Sun from behind the camera and above, so the lines are lit on the side we see.
	var sun := _world.get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		var ahead := (_aim - _from) * Vector3(1, 0, 1)
		sun.global_transform = Transform3D(Basis.looking_at(ahead.normalized() + Vector3.DOWN * 0.8), sun.global_position)


func _process(_delta: float) -> void:
	if _world == null:
		return
	_ticks += 1
	_place_camera(clampf(float(_ticks - 20) / 90.0, 0.0, 1.0))


func _place_camera(s: float) -> void:
	var eased := s * s * (3.0 - 2.0 * s)
	_camera.global_position = _from.lerp(_to, eased)
	_camera.look_at(_aim.lerp(VoxelWorld.spawn_of(_world, OUT + Vector3(0, 0.9, -6)), eased * 0.85))


func _post(x: float, z: float, height: float, width: float) -> Vector3:
	var base := VoxelWorld.spawn_of(_world, OUT + Vector3(x, 0, z))
	var post := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, height + 0.5, width)
	box.material = _post_material
	post.mesh = box
	add_child(post)
	# Half a metre into the ground, so a slope never shows a gap under it.
	post.global_position = base + Vector3.UP * (height - 0.5) * 0.5
	return base


## Posts at `xs` along a row `z` metres out, with a strand at each height in `strands`.
func _fence(z: float, xs: Array, height: float, strands: Array, kind: StringName) -> Array:
	var bases: Array[Vector3] = []
	for x: float in xs:
		bases.append(_post(x, z, height, 0.12 if height < 3.0 else 0.25))
	var spans := []
	for i in bases.size() - 1:
		for h: float in strands:
			spans.append({"from": bases[i] + Vector3(0, h, 0), "to": bases[i + 1] + Vector3(0, h, 0), "kind": kind})
	return spans


## Two posts with a cable between their tops and a guy wire from one top to a ground stake.
func _cable(z: float) -> Array:
	var left := _post(-14.0, z, 6.0, 0.2)
	var right := _post(12.0, z, 6.0, 0.2)
	var stake := VoxelWorld.spawn_of(_world, OUT + Vector3(18.0, 0.1, z - 2.0))
	return [
		{"from": left + Vector3(0, 5.9, 0), "to": right + Vector3(0, 5.9, 0), "kind": &"steel_cable"},
		{"from": right + Vector3(0, 5.9, 0), "to": stake, "kind": &"steel_cable"},
	]


## Tall towers with three high-voltage lines each: two on a crossarm, one on the top.
func _towers(z: float, xs: Array) -> Array:
	var tops: Array[Vector3] = []
	for x: float in xs:
		var base := _post(x, z, 19.2, 0.9)
		var arm := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.4, 0.4, 7.5)
		box.material = _post_material
		arm.mesh = box
		add_child(arm)
		arm.global_position = base + Vector3(0, 17.5, 0)
		tops.append(base + Vector3(0, 17.3, 0))
	var spans := []
	for i in tops.size() - 1:
		# Seen from the front, lines side by side on one arm would sit on top of each other,
		# so the middle one hangs higher.
		for at: Vector3 in [Vector3(0, 0, -3), Vector3(0, 1.8, 0), Vector3(0, 0, 3)]:
			spans.append({"from": tops[i] + at, "to": tops[i + 1] + at, "kind": &"high_voltage"})
	return spans
