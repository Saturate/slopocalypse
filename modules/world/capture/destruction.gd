extends Node3D
## Capture setup: the road and trees breaking. The road before and after explosions, a
## close look into a crater in the road, trees nearby falling, then lying where they fell
## and drying out to bare branches, and a close look at the broken stump.

const WORLD := "res://modules/world/scenes/world.tscn"
const FRAMES_PER_SHOT := 120
const AT_Z := -60.0

var _camera := Camera3D.new()
var _ticks := 0
var _current := -1
var _world: Node3D
var _voxels: VoxelWorld
var _scenery: SceneryScatter
var _road: Vector3
var _trees: Array[Vector2i] = []


func _ready() -> void:
	_world = await VoxelWorld.add_and_wait(self, WORLD)
	_voxels = _world.get_node("Terrain")
	_scenery = _world.get_node("Scenery")
	_voxels.dug.connect(_scenery.on_dug)
	var heights := _voxels.heights
	_road = Vector3(heights.road.x_at(AT_Z), heights.road.height_at(AT_Z), AT_Z)
	_camera.fov = 70.0
	_camera.far = 900.0
	add_child(_camera)
	_camera.current = true
	_camera.add_child(_voxels.make_viewer())
	_look(_road + Vector3(5.0, 4.0, 12.0), _road)
	_go(0)


func _look(at: Vector3, target: Vector3) -> void:
	_camera.global_position = at
	_camera.look_at(target)
	_scenery.update_around([at, target], INF)
	_voxels.update_around([at, target], INF)


func _process(_delta: float) -> void:
	if _scenery == null:
		return
	_ticks += 1
	var shot := (_ticks + FRAMES_PER_SHOT / 2) / FRAMES_PER_SHOT - 1
	if shot != _current:
		_go(shot)


## The trees standing nearest the road point, closest first.
func _nearest_trees(count: int) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for i: int in _scenery.loaded_chunks():
		for t in _scenery.tree_count(i):
			found.append(Vector2i(i, t))
	found.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (_scenery.tree_position(a) as Vector3).distance_to(_road) < (_scenery.tree_position(b) as Vector3).distance_to(_road))
	return found.slice(0, count)


## A tree near the road standing on its own, so its fall is easy to see.
func _lone_tree() -> Vector2i:
	var near := _nearest_trees(60)
	var best := near[0]
	var best_gap := 0.0
	for id in near:
		var at: Vector3 = _scenery.tree_position(id)
		# Down the road, away from the mountain over the tunnel.
		if at.distance_to(_road) > 70.0 or at.z > _road.z:
			continue
		var gap := INF
		for other in near:
			if other != id:
				gap = minf(gap, at.distance_to(_scenery.tree_position(other) as Vector3))
		if gap > best_gap:
			best_gap = gap
			best = id
	return best


func _go(shot: int) -> void:
	_current = shot
	match shot:
		0:
			_look(_road + Vector3(5.0, 4.0, 12.0), _road)
		1:
			_voxels.server_dig(_road + Vector3(0.0, 0.3, 0.0), 2.2)
			_voxels.server_dig(_road + Vector3(-2.5, 0.3, -6.0), 1.6)
			_voxels.server_dig(_road + Vector3(3.0, 0.3, 4.0), 0.9)
		2:
			_look(_road + Vector3(2.5, 2.2, 3.5), _road + Vector3(0.0, -0.8, 0.0))
		3:
			_trees = [_lone_tree()]
			_look(_tree_view(16.0, 4.0), _tree_target())
		4:
			# Shot through at chest height: bites first, then the cut there.
			var tree := _trees[0]
			var at: Vector3 = _scenery.tree_position(tree)
			var body := _scenery.chunk_node(tree.x).get_node("Collision")
			for n in 12:
				var hit := at + Vector3(randf_range(-0.2, 0.2), 1.2 + randf_range(-0.15, 0.15), 0.0) - _fall_direction() * 0.25
				_scenery.bite_tree(body, hit, hit - _fall_direction() * 10.0)
			_scenery.fell_tree(tree, _fall_direction(), 1.2)
		5:
			var stump: Vector3 = _scenery.tree_position(_trees[0])
			var eye := stump - _fall_direction() * 4.5 + _fall_direction().cross(Vector3.UP) * 2.0
			_look(Vector3(eye.x, _voxels.ground_height(eye.x, eye.z) + 1.8, eye.z), stump + _fall_direction() * 2.0 + Vector3.UP * 0.8)
		6, 7, 8:
			# The same fallen top drying out: a third, two thirds, then bare branches.
			_age(_trees[0], (shot - 5) / 3.0)
		9:
			# Close on the stump: broken, not sawn.
			var foot: Vector3 = _scenery.tree_position(_trees[0])
			var side := _fall_direction().cross(Vector3.UP)
			var eye := foot + side * 1.6 - _fall_direction() * 0.6
			_look(Vector3(eye.x, _voxels.ground_height(eye.x, eye.z) + 1.7, eye.z), foot + Vector3.UP * 1.0)


## Makes tree `id` look as if it fell `share` of the wither time ago.
func _age(id: Vector2i, share: float) -> void:
	var seconds := float(Data.load_json("res://modules/world/data/world.json")["scatter"]["tree_wither_seconds"]) * share
	var info: Dictionary = _scenery.felled()[id]
	info["since"] = Time.get_ticks_msec() - int(seconds * 1000.0) - 10


## Falls straight away from the road.
func _fall_direction() -> Vector3:
	var d := (_scenery.tree_position(_trees[0]) as Vector3) - _road
	return Vector3(d.x, 0.0, d.z).normalized()


## Side-on to the fall, `distance` away and `height` up.
func _tree_view(distance: float, height: float) -> Vector3:
	var d := _fall_direction()
	var side := d.cross(Vector3.UP)
	var at := (_scenery.tree_position(_trees[0]) as Vector3) + side * distance + d * 3.0
	return Vector3(at.x, _voxels.ground_height(at.x, at.z) + height, at.z)


func _tree_target() -> Vector3:
	return (_scenery.tree_position(_trees[0]) as Vector3) + _fall_direction() * 4.0 + Vector3.UP * 2.0
