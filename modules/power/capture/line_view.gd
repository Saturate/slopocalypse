extends Node3D
## Capture base: a stretch of one of the default map's power lines, its towers and wires,
## seen from beside it and drifting along it over the frames, lit from behind the camera and
## to one side. Each capture names the line's kind, which tower to stand by and where to look;
## `LINE_INDEX` picks another line of that kind (the first when unset).

const WORLD := "res://modules/world/scenes/world.tscn"
const POWER := "res://modules/power/power_module.gd"
const WIRES := "res://modules/wires/wires_module.gd"
const SITES := "res://modules/sites/sites_module.gd"
const EYE := 1.8
const SUN_SIDE := 0.7
const SUN_HIGH := 0.6

var kind := "high_voltage"
## Which tower of the line to stand by (from its source; negative counts from the far end).
var tower := 1
## Metres out to the side of the line, and back along it, the camera starts and ends.
var side := 40.0
var back_from := 30.0
var back_to := 10.0
## The tower looked at, counted on from `tower`, and how high on it (metres over its foot).
var ahead := 1
var look_up := 12.0
var fov := 65.0

var _camera := Camera3D.new()
var _terrain: VoxelWorld
var _points: Array = []
var _t := 0.0


func _ready() -> void:
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	_terrain = world.get_node("Terrain")
	var wires: Node = (load(WIRES) as GDScript).new()
	add_child(wires)
	var sites: Node = (load(SITES) as GDScript).new()
	add_child(sites)
	var power: Node = (load(POWER) as GDScript).new()
	add_child(power)
	EventBus.publish(&"world.ready", {"spawn": VoxelWorld.spawn_of(world)})
	# Every frame of the sheet shows the line, not the towers going up.
	power.call(&"build_all")
	sites.call(&"build_all")
	wires.call(&"flush")
	var wanted := int(OS.get_environment("LINE_INDEX")) if OS.has_environment("LINE_INDEX") else 0
	var seen := 0
	for line: Dictionary in _terrain.map_power_lines():
		if line["kind"] == kind:
			if seen == wanted:
				_points = line["points"]
				break
			seen += 1
	if _points.size() < 2:
		push_error("no %s line %d on this map" % [kind, wanted])
		return
	tower = clampi(tower if tower >= 0 else _points.size() + tower, 0, _points.size() - 1)
	_camera.fov = fov
	_camera.far = 2500.0
	add_child(_camera)
	_camera.current = true
	_camera.add_child(_terrain.make_viewer())
	_place(0.0)
	_light_from_behind(world.get_node("Sun") as DirectionalLight3D)
	var focus: Array[Vector3] = [_camera.global_position]
	for p: Vector3 in _points:
		focus.append(p)
	_terrain.update_around(focus, INF)
	(world.get_node("Scenery") as SceneryScatter).update_around(focus, INF)


func _process(delta: float) -> void:
	if _points.size() < 2:
		return
	_t += delta
	_place(clampf(_t / 3.0, 0.0, 1.0))


## Along the line at the tower stood by, and across it to the left.
func _axes() -> Array[Vector3]:
	var a: Vector3 = _points[tower]
	var b: Vector3 = _points[mini(tower + 1, _points.size() - 1)] if tower + 1 < _points.size() else _points[tower] + (_points[tower] - _points[tower - 1])
	var along := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
	return [along, Vector3(-along.z, 0.0, along.x)]


func _place(share: float) -> void:
	var axes := _axes()
	var foot: Vector3 = _points[tower]
	var at := foot - axes[0] * lerpf(back_from, back_to, share) + axes[1] * side
	at.y = _terrain.surface_height(at.x, at.z) + EYE
	_camera.global_position = at
	var target: Vector3 = _points[clampi(tower + ahead, 0, _points.size() - 1)]
	_camera.look_at(target + Vector3.UP * look_up)


func _light_from_behind(sun: DirectionalLight3D) -> void:
	var ahead_dir := -_camera.global_basis.z
	ahead_dir.y = 0.0
	var flat := ahead_dir.normalized().rotated(Vector3.UP, SUN_SIDE)
	var shine := (flat * cos(SUN_HIGH) + Vector3.DOWN * sin(SUN_HIGH)).normalized()
	sun.global_basis = Basis.looking_at(shine, Vector3.UP)
