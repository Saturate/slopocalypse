class_name MapApi
extends Node
## The map viewer's API on a server's admin pages (#448): the map recipes, and renders of a
## recipe and seed (MapRender) with their stats, behind the web module's password. A render
## takes seconds, so it runs on a worker thread, one at a time, and the request waits for it
## without holding up a frame. Renders are kept for a while by a key of their inputs.
##   GET  /admin/api/v1/maps                  {maps: [names]}
##   GET  /admin/api/v1/maps/<name>           the recipe (JSON)
##   POST /admin/api/v1/maps/render           {map, seed, pixels?, layers?, recipe?} -> {image, stats}
##   GET  /admin/api/v1/maps/image/<key>.png  a render's image
## Saving recipes stays in the local viewer (tools/map-viewer.ts): a server's files are its own.

const MAPS_DIR := "res://modules/world/data/maps"
const PATH := "/admin/api/v1/maps"
const MIN_PIXELS := 64
const MAX_PIXELS := 1024
## Renders kept in memory, newest last; older ones are dropped.
const KEEP_RENDERS := 12
const LAYERS: Array[String] = ["zones", "settlements", "roads", "earthworks"]

## key -> {png (PackedByteArray), stats}
var _renders: Dictionary[String, Dictionary] = {}
var _order: Array[String] = []
## Renders that could not be built (a broken edited recipe): answered with an error at once.
var _failed: Dictionary[String, bool] = {}
## The render on the worker thread: {key, task, result} or empty.
var _job: Dictionary = {}


func _ready() -> void:
	EventBus.subscribe(&"web.ready", _on_web_ready)
	var web := get_tree().get_first_node_in_group(&"web_api")
	if web != null:
		_on_web_ready({"web": web})


func _exit_tree() -> void:
	EventBus.unsubscribe(&"web.ready", _on_web_ready)
	if not _job.is_empty():
		WorkerThreadPool.wait_for_task_completion(int(_job["task"]))


func _on_web_ready(p: Dictionary) -> void:
	var web: Node = p["web"]
	web.call(&"add_admin_page", PATH, "", handle)


## Names of the map recipes on this server.
static func names() -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(MAPS_DIR):
		if f.ends_with(".json"):
			out.append(f.get_basename())
	out.sort()
	return out


func handle(req: Dictionary) -> Variant:
	var rest := str(req["path"]).trim_prefix(PATH).trim_prefix("/")
	var method := str(req["method"])
	if rest.is_empty() and method != "POST":
		return _json(200, {"maps": names()})
	if rest == "render" and method == "POST":
		return _start_render(str(req["body"]))
	if rest.begins_with("image/") and method != "POST":
		var key := rest.trim_prefix("image/").trim_suffix(".png")
		if not _renders.has(key):
			return [404, "text/plain", "no such render (renders are kept for a while only)"]
		return [200, "image/png", _renders[key]["png"]]
	if names().has(rest) and method != "POST":
		return [200, "application/json", FileAccess.get_file_as_string(MAPS_DIR.path_join(rest + ".json"))]
	return [404, "text/plain", "not found"]


func _start_render(body: String) -> Variant:
	# A JSON instance reports a bad body without logging an engine error for every one.
	var parser := JSON.new()
	var asked: Variant = parser.data if parser.parse(body) == OK else null
	if not asked is Dictionary:
		return _json(400, {"error": "send a JSON object"})
	var req: Dictionary = asked
	var map := str(req.get("map", ""))
	if not names().has(map):
		return _json(400, {"error": "no map recipe called %s" % map})
	var seed_value: Variant = req.get("seed", 1)
	if not (seed_value is float or seed_value is int) or float(seed_value) != floorf(float(seed_value)) or float(seed_value) < 0.0 or float(seed_value) > 2147483647.0:
		return _json(400, {"error": "seed must be a whole number from 0"})
	var asked_pixels: Variant = req.get("pixels", 512)
	if not (asked_pixels is float or asked_pixels is int):
		return _json(400, {"error": "pixels must be a number"})
	var pixels := int(asked_pixels)
	if pixels < MIN_PIXELS or pixels > MAX_PIXELS:
		return _json(400, {"error": "pixels must be %d to %d" % [MIN_PIXELS, MAX_PIXELS]})
	var layers := PackedStringArray()
	var asked_layers: Variant = req.get("layers", LAYERS)
	if not asked_layers is Array:
		return _json(400, {"error": "layers must be a list"})
	for l: Variant in asked_layers:
		if not LAYERS.has(str(l)):
			return _json(400, {"error": "unknown layer %s" % l})
		layers.append(str(l))
	var recipe: Variant = req.get("recipe")
	if recipe == null:
		recipe = JSON.parse_string(FileAccess.get_file_as_string(MAPS_DIR.path_join(map + ".json")))
	if not recipe is Dictionary:
		return _json(400, {"error": "recipe must be a JSON object"})
	var problem := MapRender.check(recipe)
	if not problem.is_empty():
		return _json(400, {"error": "recipe: " + problem})
	var key := ("%s|%d|%d|%s|%s" % [map, int(seed_value), pixels, ",".join(layers), JSON.stringify(recipe, "", true)]).sha256_text().substr(0, 20)
	if _renders.has(key):
		return _json(200, _answer(key))
	var job_recipe: Dictionary = recipe
	var job_seed := int(seed_value)
	return {"wait": func() -> Variant: return _work(key, job_recipe, job_seed, pixels, layers)}


## Called each frame for a waiting request: starts its render when the thread is free, and
## answers once it is done.
func _work(key: String, recipe: Dictionary, seed_value: int, pixels: int, layers: PackedStringArray) -> Variant:
	if _renders.has(key):
		return _json(200, _answer(key))
	if _failed.has(key):
		return _json(400, {"error": "the recipe could not be built; check its fields"})
	if _job.is_empty():
		# Both keys exist before the task starts: the worker writes "result" while this thread
		# stores "task", and adding a key then could resize the dictionary under it.
		var job := {"key": key, "result": {}, "task": -1}
		job["task"] = WorkerThreadPool.add_task(func() -> void: job["result"] = MapRender.make(recipe, seed_value, pixels, layers), false, "map render")
		_job = job
		return null
	if not WorkerThreadPool.is_task_completed(int(_job["task"])):
		return null
	WorkerThreadPool.wait_for_task_completion(int(_job["task"]))
	var done: Dictionary = _job
	_job = {}
	var raw: Variant = done["result"]
	if not raw is Dictionary or (raw as Dictionary).is_empty():
		if _failed.size() >= KEEP_RENDERS:
			_failed.clear()
		_failed[str(done["key"])] = true
		return _json(400, {"error": "the recipe could not be built; check its fields"}) if str(done["key"]) == key else null
	var result: Dictionary = raw
	_keep(str(done["key"]), (result["image"] as Image).save_png_to_buffer(), result["stats"])
	return _json(200, _answer(key)) if _renders.has(key) else null


func _keep(key: String, png: PackedByteArray, stats: Dictionary) -> void:
	_renders[key] = {"png": png, "stats": stats}
	_order.append(key)
	while _order.size() > KEEP_RENDERS:
		_renders.erase(_order.pop_front())


func _answer(key: String) -> Dictionary:
	return {"image": "%s/image/%s.png" % [PATH, key], "stats": _renders[key]["stats"]}


static func _json(status: int, data: Dictionary) -> Array:
	return [status, "application/json", JSON.stringify(data, "", false)]
