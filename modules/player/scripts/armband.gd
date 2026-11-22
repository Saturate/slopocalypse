class_name Armband
extends RefCounted
## The coloured band everyone wears on both upper arms (#447), so co-op players, civilians and
## soldiers of each faction are told apart in a fight. Who is who is the server's call: the
## `civilian` and `faction` metas the enemies module sets on every copy as it spawns. A body
## with neither is a player. Clients only draw it; the colours are in armbands.json, which
## holds a second table for colour-blind players, picked by the `colour_blind` setting.

const CONFIG := "res://modules/player/data/armbands.json"
const TABLE := {"players": TYPE_ARRAY, "civilians": TYPE_ARRAY, "enemies": TYPE_ARRAY, "factions": TYPE_DICTIONARY}
const REQUIRED := {"players": TYPE_ARRAY, "civilians": TYPE_ARRAY, "enemies": TYPE_ARRAY, "factions": TYPE_DICTIONARY, "glow": TYPE_FLOAT}
## The player's setting (core/settings.gd) that swaps in the colour-blind table.
const SETTING := "colour_blind"
const BAND := "Body/Skeleton/Band"

## Off on a dedicated server, which draws nothing; tests turn it on.
static var enabled := DisplayServer.get_name() != "headless"
static var _config: Dictionary = {}
static var _loaded := false
## One material per kind of person (`kind_of`), shared by every band of that kind, so
## switching the colour set repaints them all at once.
static var _materials: Dictionary = {}


static func config() -> Dictionary:
	if not _loaded:
		use_config(Data.load_json(CONFIG))
	return _config


## Takes `data` as the colours if it has every field, else none (tests and tweaks).
static func use_config(data: Variant) -> void:
	_loaded = true
	_materials.clear()
	var ok: bool = data is Dictionary and Data.require(CONFIG, data, REQUIRED)
	# Optional, so a tweaked copy of the file from before the colour-blind table still works.
	if ok and (data as Dictionary).has("colour_blind"):
		var blind: Variant = data["colour_blind"]
		ok = blind is Dictionary and Data.require(CONFIG + " colour_blind", blind, TABLE)
	_config = data if ok else {}


## The colours in use: the default table, or the colour-blind one when the player chose it.
static func palette() -> Dictionary:
	var cfg := config()
	if cfg.is_empty():
		return {}
	return cfg["colour_blind"] if bool(Settings.value(SETTING)) and cfg.has("colour_blind") else cfg


## Which band `person` wears: "players", "civilians", "enemies" or "factions/<id>". Who is who
## is the server's call, through the metas it sets.
static func kind_of(person: Node) -> String:
	if person.get_meta(&"civilian", false):
		return "civilians"
	var faction := str(person.get_meta(&"faction", ""))
	if not faction.is_empty():
		return "factions/" + faction
	if person.has_meta(&"team"):
		return "enemies"
	return "players"


## The band colour `person` wears in the colour set in use.
static func colour_for(person: Node) -> Color:
	return colour_of(kind_of(person))


## The colour of a kind of band (`kind_of`) in the colour set in use. A faction without a
## colour of its own reads as plain enemies.
static func colour_of(kind: String) -> Color:
	var table := palette()
	if table.is_empty():
		return Color.WHITE
	if kind.begins_with("factions/"):
		var factions: Dictionary = table["factions"]
		return _colour(factions.get(kind.trim_prefix("factions/"), table["enemies"]))
	return _colour(table.get(kind, table["enemies"]))


## Colours `person`'s band by who they are. The band is its own mesh, so a uniform tint on the
## body leaves it alone.
static func apply(person: Node) -> void:
	var band := person.get_node_or_null(BAND) as GeometryInstance3D
	if not enabled or band == null or config().is_empty():
		return
	band.material_override = _material(kind_of(person))


## Repaints every band already worn (and every corpse's, which shares the material) in the
## colour set in use; the player module calls it when the setting changes.
static func repaint() -> void:
	for kind: String in _materials:
		_paint(_materials[kind], colour_of(kind))


static func _material(kind: String) -> StandardMaterial3D:
	if _materials.has(kind):
		# The setting may have changed while no player module was listening (on the title).
		var cached: StandardMaterial3D = _materials[kind]
		_paint(cached, colour_of(kind))
		return cached
	var m := StandardMaterial3D.new()
	m.roughness = 0.85
	# A little light of its own so the colour survives a moonlit night without lighting
	# anything around it.
	m.emission_enabled = true
	m.emission_energy_multiplier = float(config()["glow"])
	_paint(m, colour_of(kind))
	_materials[kind] = m
	return m


static func _paint(m: StandardMaterial3D, colour: Color) -> void:
	m.albedo_color = colour
	m.emission = colour


static func _colour(c: Variant) -> Color:
	var a: Array = c if c is Array else []
	if a.size() < 3:
		return Color.WHITE
	return Color(float(a[0]), float(a[1]), float(a[2]))
