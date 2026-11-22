class_name Armband
extends RefCounted
## The coloured band everyone wears on both upper arms (#447), so co-op players, civilians and
## soldiers of each faction are told apart in a fight. Who is who is the server's call: the
## `civilian` and `faction` metas the enemies module sets on every copy as it spawns. A body
## with neither is a player. Clients only draw it; the colours are in armbands.json.

const CONFIG := "res://modules/player/data/armbands.json"
const REQUIRED := {"players": TYPE_ARRAY, "civilians": TYPE_ARRAY, "enemies": TYPE_ARRAY, "factions": TYPE_DICTIONARY, "glow": TYPE_FLOAT}
const BAND := "Body/Skeleton/Band"

## Off on a dedicated server, which draws nothing; tests turn it on.
static var enabled := DisplayServer.get_name() != "headless"
static var _config: Dictionary = {}
static var _loaded := false
## One material per colour, shared by every band of that colour.
static var _materials: Dictionary = {}


static func config() -> Dictionary:
	if not _loaded:
		use_config(Data.load_json(CONFIG))
	return _config


## Takes `data` as the colours if it has every field, else none (tests and tweaks).
static func use_config(data: Variant) -> void:
	_loaded = true
	_materials.clear()
	_config = data if data is Dictionary and Data.require(CONFIG, data, REQUIRED) else {}


## A faction without a colour of its own reads as plain enemies.
static func colour_for(person: Node) -> Color:
	var cfg := config()
	if cfg.is_empty():
		return Color.WHITE
	if person.get_meta(&"civilian", false):
		return _colour(cfg["civilians"])
	var faction := str(person.get_meta(&"faction", ""))
	var factions: Dictionary = cfg["factions"]
	if factions.has(faction):
		return _colour(factions[faction])
	if not faction.is_empty() or person.has_meta(&"team"):
		return _colour(cfg["enemies"])
	return _colour(cfg["players"])


## Colours `person`'s band by who they are. The band is its own mesh, so a uniform tint on the
## body leaves it alone.
static func apply(person: Node) -> void:
	var band := person.get_node_or_null(BAND) as GeometryInstance3D
	if not enabled or band == null or config().is_empty():
		return
	band.material_override = _material(colour_for(person))


static func _material(colour: Color) -> StandardMaterial3D:
	var key := colour.to_html(false)
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 0.85
	# A little light of its own so the colour survives a moonlit night without lighting
	# anything around it.
	m.emission_enabled = true
	m.emission = colour
	m.emission_energy_multiplier = float(config()["glow"])
	_materials[key] = m
	return m


static func _colour(c: Variant) -> Color:
	var a: Array = c if c is Array else []
	if a.size() < 3:
		return Color.WHITE
	return Color(float(a[0]), float(a[1]), float(a[2]))
