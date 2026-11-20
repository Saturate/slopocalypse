class_name WorldMaps
extends RefCounted
## Which generated map this game plays (#472), built once and shared: the terrain, the
## scenery and the modules placing things all read the same MapShape. Nothing selected: the
## strip is played. Runs without autoloads (the voxel world and scenery read it in _ready).

const MAPS_DIR := "res://modules/world/data/maps"

static var _recipe_name := ""
static var _seed := 0
static var _shape: MapShape


static func select(recipe_name: String, seed_value: int) -> void:
	if recipe_name != _recipe_name or seed_value != _seed:
		_shape = null
	_recipe_name = recipe_name
	_seed = seed_value


static func clear() -> void:
	_recipe_name = ""
	_shape = null


static func is_selected() -> bool:
	return not _recipe_name.is_empty()


static func recipe_name() -> String:
	return _recipe_name


static func seed_value() -> int:
	return _seed


## The selected map's shape, built on first use; null with none selected or a broken recipe.
static func shape() -> MapShape:
	if _shape != null or _recipe_name.is_empty():
		return _shape
	var path := MAPS_DIR.path_join(_recipe_name + ".json")
	var recipe: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	# Said once by whoever selected it (the world module falls back to the strip).
	if not recipe is Dictionary or not MapRender.check(recipe).is_empty():
		return null
	var built := MapRender.build(recipe, _seed)
	built["recipe"] = recipe
	_shape = MapShape.new(built, (recipe as Dictionary).get("water", {}))
	return _shape
