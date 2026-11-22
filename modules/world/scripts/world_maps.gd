class_name WorldMaps
extends RefCounted
## Which generated map this game plays (#472), built once and shared: the terrain, the
## scenery and the modules placing things all read the same MapShape. Runs without autoloads
## (the voxel world and scenery read it in _ready).
##
## A game builds it on a worker thread (`start_build`, then `is_building` each frame until it
## says false), so the main loop keeps polling the network and drawing for the second or two
## it takes (#515). `shape()` blocks until it is built: for tests, captures and tools, and for
## the world scene, which the world module only loads once the build is done.

const MAPS_DIR := "res://modules/world/data/maps"
const CONFIG := "res://modules/world/data/world.json"

static var _recipe_name := ""
static var _seed := 0
static var _shape: MapShape
## The build on the worker pool: {task, result}; empty when none is running. The worker only
## writes `result`, a key that exists before it starts; this thread reads it only after
## waiting for the task.
static var _job: Dictionary = {}


static func select(recipe_name: String, seed_value: int) -> void:
	if recipe_name != _recipe_name or seed_value != _seed:
		_drop_job()
		_shape = null
	_recipe_name = recipe_name
	_seed = seed_value


## The map `world.json` `map` names (recipe and seed): what a world built without the world
## module (a test, a capture) stands on. False when that section is missing.
static func select_default() -> bool:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	if not data is Dictionary or not (data as Dictionary).get("map") is Dictionary:
		return false
	var cfg: Dictionary = data["map"]
	if not cfg.get("recipe") is String or not (cfg.get("seed") is float or cfg.get("seed") is int):
		return false
	select(str(cfg["recipe"]), int(cfg["seed"]))
	return true


## The selected map, or the default one when none is selected; null when that recipe is
## missing or broken.
static func shape_or_default() -> MapShape:
	if not is_selected():
		select_default()
	return shape()


## Waits for a build still running (a worker task must be waited for), so this blocks for
## up to a build's time when a game is left while its map builds.
static func clear() -> void:
	_drop_job()
	_recipe_name = ""
	_shape = null


static func is_selected() -> bool:
	return not _recipe_name.is_empty()


static func recipe_name() -> String:
	return _recipe_name


static func seed_value() -> int:
	return _seed


## Whether the recipe `name` exists and passes MapRender.check: what the map would be built
## from. Cheap next to the build, so a game can turn a bad name away before starting it.
static func is_playable(name: String) -> bool:
	return _recipe(name) != null


## Starts building the selected map on a worker thread; does nothing when it is built or
## building. False with nothing selected or a missing or broken recipe.
static func start_build() -> bool:
	if _shape != null or not _job.is_empty():
		return true
	var recipe: Variant = _recipe(_recipe_name)
	if recipe == null:
		return false
	var job := {"task": -1, "result": null}
	var seed_value := _seed
	job["task"] = WorkerThreadPool.add_task(func() -> void: job["result"] = _build(recipe, seed_value), false, "map build")
	_job = job
	return true


## True while a build started by `start_build` is running; once it is done, collects it so
## `shape()` answers at once.
static func is_building() -> bool:
	if _job.is_empty():
		return false
	if not WorkerThreadPool.is_task_completed(int(_job["task"])):
		return true
	_collect()
	return false


## The selected map's shape, built on first use (or waited for when a build is running); null
## with none selected or a broken recipe.
static func shape() -> MapShape:
	if not _job.is_empty():
		_collect()
	if _shape != null or _recipe_name.is_empty():
		return _shape
	var recipe: Variant = _recipe(_recipe_name)
	# Said once by whoever selected it (the world module).
	if recipe == null:
		return null
	_shape = _build(recipe, _seed)
	return _shape


## Runs on a worker thread from `start_build`: touches no static state, no node and no
## autoload, so it answers exactly what a build on the main thread would.
static func _build(recipe: Dictionary, seed_value: int) -> MapShape:
	var built := MapRender.build(recipe, seed_value)
	built["recipe"] = recipe
	return MapShape.new(built, recipe.get("water", {}))


static func _recipe(name: String) -> Variant:
	if name.is_empty():
		return null
	var path := MAPS_DIR.path_join(name + ".json")
	var recipe: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not recipe is Dictionary or not MapRender.check(recipe).is_empty():
		return null
	return recipe


static func _collect() -> void:
	WorkerThreadPool.wait_for_task_completion(int(_job["task"]))
	var built: Variant = _job["result"]
	_job = {}
	if built is MapShape:
		_shape = built


static func _drop_job() -> void:
	if not _job.is_empty():
		WorkerThreadPool.wait_for_task_completion(int(_job["task"]))
		_job = {}
