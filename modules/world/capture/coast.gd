extends Node3D
## Capture setup: the island's coast (#454), one shot every SHOT_FRAMES frames: the camp by
## the water from above with its harbour spot, the harbour's shore at eye height, a beach, a
## cliff from the sea, the sea from a hill near the coast, and the island from a swimmer
## out past the harbour. `-- --map=mixed --seed=1` films a hillier map, whose hills meet
## the sea in cliffs.

const WORLD := "res://modules/world/scenes/world.tscn"
const SHOT_FRAMES := 60
const EYE := 1.7

var _camera := Camera3D.new()
var _ticks := 0
var _terrain: VoxelWorld
var _scenery: SceneryScatter
## Each [camera, target], in world space.
var _shots: Array[Array] = []
## The way the sunlight falls, on the ground plane (zero without a sun).
var _light := Vector2.ZERO


func _ready() -> void:
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	_terrain = world.get_node("Terrain") as VoxelWorld
	_scenery = world.get_node("Scenery") as SceneryScatter
	var map := _terrain.heights as MapShape
	if map == null or map.harbour().is_empty():
		Log.info(&"capture", "%s: this map has no coast to film" % get_script().resource_path)
		get_tree().quit(0)
		return
	var suns := get_tree().root.find_children("*", "DirectionalLight3D", true, false)
	if not suns.is_empty():
		var travel := -(suns[0] as Node3D).global_transform.basis.z
		_light = Vector2(travel.x, travel.z).normalized()
	_plan(map)
	_camera.fov = 70.0
	_camera.far = 2500.0
	add_child(_camera)
	_camera.current = true
	_camera.add_child(_terrain.make_viewer())
	_show(0)


func _plan(map: MapShape) -> void:
	var land := map.land
	var sea := land.sea_level
	var h := map.harbour()
	var root: Vector3 = h["root"]
	var facing: Vector3 = h["facing"]
	var end: Vector3 = h["end"]
	var camp: Vector3 = map.camp_pad()["centre"]
	var to_sea := Vector3(root.x - camp.x, 0.0, root.z - camp.z).normalized()
	_shots.append([camp - to_sea * 45.0 + Vector3.UP * 30.0, camp + to_sea * 20.0])
	_shots.append([_on_ground(root - facing * 8.0, EYE), end + facing * 40.0 + Vector3.UP * 2.0])
	var beach := _shore(land, func(p: Vector2, out: Vector2) -> float: return land.sand(p.x, p.y) + land.sand(p.x - out.x * 6.0, p.y - out.y * 6.0))
	var b_out := Vector3(beach.x, 0.0, beach.z).normalized()
	var along := b_out.cross(Vector3.UP)
	_shots.append([_on_ground(beach - b_out * 14.0, EYE), Vector3(beach.x, sea, beach.z) + b_out * 25.0 + along * 35.0])
	# Cliffs seen with the sun behind the camera, out at sea looking in.
	var cliff := _shore(land, func(p: Vector2, out: Vector2) -> float:
		var top := p - out * 4.0
		var lit := (-out).dot(_light) if _light != Vector2.ZERO else 0.0
		return land.rock(top.x, top.y) * 2.0 + clampf((land.land_height(top.x, top.y) - sea) / 6.0, 0.0, 2.0) + lit * 0.5)
	var c_out := Vector3(cliff.x, 0.0, cliff.z).normalized()
	var c_top := cliff - c_out * 10.0
	_shots.append([Vector3(cliff.x, sea + 3.0, cliff.z) + c_out * 70.0, Vector3(c_top.x, land.land_height(c_top.x, c_top.z), c_top.z)])
	var hill := _hill(land)
	var h_out := _to_sea(land, hill)
	# Over the treetops, as from the top of a lookout.
	var brow := _on_ground(hill + h_out * 40.0, 30.0)
	var shore := Vector3(brow.x, sea, brow.z)
	while not land.is_sea(shore.x, shore.z) and shore.distance_to(Vector3(brow.x, sea, brow.z)) < 1000.0:
		shore += h_out * 10.0
	_shots.append([brow, shore + h_out * 120.0])
	_shots.append([end + facing * 35.0 + Vector3.UP * 0.4, root + Vector3.UP * 4.0 - facing * 40.0])


## The point at `p`'s x and z `above` metres over the ground.
func _on_ground(p: Vector3, above: float) -> Vector3:
	return Vector3(p.x, _terrain.ground_height(p.x, p.z) + above, p.z)


## The shore point, walking in from the map's edge along rays from the middle, that `score`
## (the point and the way out to sea) likes best, on the ground there.
func _shore(land: WorldLand, score: Callable) -> Vector3:
	var best := Vector2.ZERO
	var best_score := -INF
	for a in 180:
		var out := Vector2.from_angle(TAU * a / 180.0)
		var r := land.size / 2.0
		while r > 0.0 and land.is_sea(out.x * r, out.y * r):
			r -= 2.0
		var p := out * r
		var s := float(score.call(p, out))
		if s > best_score:
			best_score = s
			best = p
	return Vector3(best.x, _terrain.ground_height(best.x, best.y), best.y)


## The highest open ground a little way in from the coast.
func _hill(land: WorldLand) -> Vector3:
	var best := Vector3.ZERO
	var b := land.bounds()
	var step := 24.0
	var x := b.position.x
	while x < b.end.x:
		var z := b.position.y
		while z < b.end.y:
			var s := land.inland(x, z)
			# Out of the woods, so trees do not fill the view.
			if s > 150.0 and s < 450.0 and land.forest(x, z) < 0.1:
				var h := land.land_height(x, z)
				if h > best.y:
					best = Vector3(x, h, z)
			z += step
		x += step
	return _on_ground(best, 0.0)


## A way from `at` out to sea within a kilometre, the sun behind it if it can be.
func _to_sea(land: WorldLand, at: Vector3) -> Vector3:
	var best := Vector3(at.x, 0.0, at.z).normalized()
	var best_score := -INF
	for a in 72:
		var dir := Vector2.from_angle(TAU * a / 72.0)
		var r := 10.0
		while r < 1000.0:
			if land.is_sea(at.x + dir.x * r, at.z + dir.y * r):
				var score := dir.dot(_light) * 2.0 - r / 1000.0
				if score > best_score:
					best_score = score
					best = Vector3(dir.x, 0.0, dir.y)
				break
			r += 10.0
	return best


func _show(i: int) -> void:
	var shot: Array = _shots[i]
	var at: Vector3 = shot[0]
	var target: Vector3 = shot[1]
	_terrain.update_around([at, target.lerp(at, 0.5)], INF)
	_scenery.update_around([at, target.lerp(at, 0.5)], INF)
	_camera.global_position = at
	_camera.look_at(target)


func _process(_delta: float) -> void:
	if _shots.is_empty():
		return
	_ticks += 1
	if _ticks % SHOT_FRAMES == 1 and _ticks > 1:
		var i := _ticks / SHOT_FRAMES
		if i < _shots.size():
			_show(i)
