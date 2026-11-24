extends Node3D
## Capture setup: first person at the trader's stall in the camp, then the trade screen
## open with too few tokens for the dearest goods. `-- --view=` picks what it shows:
## `hover` (a good's details, its tile lit), `guns` (the Guns tab, the details of a medkit
## you carry with what it sells for), `sell` (one of your items dragged over the goods),
## `drag` (a 30 round magazine dragged from the goods over your backpack). `--size=1600x900` resizes the window first.

const WORLD := "res://modules/world/scenes/world.tscn"
const PLAYER := "res://modules/player/scenes/player.tscn"
const INVENTORY := "res://modules/inventory/inventory_module.gd"
const MISSIONS := "res://modules/missions/missions_module.gd"
const TRADER := "res://modules/trader/trader_module.gd"
## Loaded as in the game: they supply the pictures and numbers of guns, parts and sticks.
const SUPPLIERS := ["res://modules/weapons/weapons_module.gd", "res://modules/glowsticks/glowsticks_module.gd"]
const OPEN_AT := 60
## A frame later the view is set up, so the screen has laid itself out.
const VIEW_AT := OPEN_AT + 2
const TOKENS := 45

var _player: PlayerController
var _trader: Node
var _ticks := 0
var _view := ""


func _option(name: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.get_slice("=", 1)
	return ""


func _ready() -> void:
	_view = _option("view")
	var size := _option("size")
	if not size.is_empty():
		get_window().size = Vector2i(int(size.get_slice("x", 0)), int(size.get_slice("x", 1)))
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	for path: String in SUPPLIERS:
		add_child((load(path) as GDScript).new())
	add_child((load(INVENTORY) as GDScript).new())
	var missions: Node = (load(MISSIONS) as GDScript).new()
	add_child(missions)
	_trader = (load(TRADER) as GDScript).new()
	add_child(_trader)
	var spawn := (get_tree().get_first_node_in_group(&"spawn_point") as Node3D).global_position
	_player = (load(PLAYER) as PackedScene).instantiate()
	_player.set_meta(&"peer_id", 1)
	_player.add_to_group(&"players")
	add_child(_player)
	_player.global_position = spawn
	# The player module registers the local player's keys (F, Tab) in the game.
	var player_data: Variant = Data.load_json("res://modules/player/data/player.json")
	InputBindings.register((player_data as Dictionary).get("bindings", {}) if player_data is Dictionary else {}, &"player")
	EventBus.publish(&"player.spawned", {"player": _player, "local": true})
	PlayerBody.first_person(_player.get_node("Body"))
	EventBus.publish(&"world.ready", {"spawn": spawn, "camp": world.get("camp")})
	missions.call(&"server_set_tokens", 1, TOKENS)
	var stall := _trader.get_node("TraderStall") as Node3D
	# In front of the counter (its -z side), a little to one side.
	_player.global_position = stall.global_transform * Vector3(0.5, 0.2, -2.6)
	_player.set_physics_process(false)
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = _player.global_position + Vector3.UP * 1.6
	cam.look_at(stall.global_position + Vector3.UP * 1.3, Vector3.UP)
	cam.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(_delta: float) -> void:
	_ticks += 1
	if _ticks == OPEN_AT:
		EventBus.publish(&"trader.opened", {"peer": 1})
	elif _ticks == VIEW_AT:
		_set_view(_trader.get_node("TraderScreen") as TraderScreen)


func _set_view(screen: TraderScreen) -> void:
	# The desktop's own pointer may cross the window while it records; only the view set
	# here should move anything.
	screen.set_process_input(false)
	match _view:
		"hover":
			screen.call(&"_move_to", _tile_centre(screen, "gun_rifle"))
		"guns":
			screen.set_category("guns")
			var medkit: Dictionary = _first(&"rig", "medkit")
			screen.call(&"_move_to", _cell_centre(screen, "rig", medkit))
		"sell":
			var item: Dictionary = _gear().items("backpack")[0]
			screen.pick_mine({"grid": "backpack", "x": int(item["x"]), "y": int(item["y"])})
			screen.call(&"_move_to", (screen.get(&"_goods_box") as Control).get_global_rect().get_center())
		"drag":
			var tile := _tile_centre(screen, "mag_ar_30")
			screen.call(&"_move_to", tile)
			screen.call(&"_press_at", _left_press(tile))
			var backpack: Control = (screen.get(&"_gear") as GearPanel).view_of({"grid": "backpack"})
			screen.call(&"_move_to", backpack.get_global_rect().position + Vector2(3.5, 4.5) * GearPanel.CELL)


func _gear() -> InventoryGear:
	return get_tree().get_first_node_in_group(&"inventory_api").call(&"grid_of", 1)


func _first(grid: StringName, item: String) -> Dictionary:
	for placed: Dictionary in _gear().items(grid):
		if str(placed["item"]) == item:
			return placed
	return {}


func _tile_centre(screen: TraderScreen, item: String) -> Vector2:
	return ((screen.get(&"_tiles") as Dictionary)[item] as Control).get_global_rect().get_center()


func _cell_centre(screen: TraderScreen, grid: String, placed: Dictionary) -> Vector2:
	var view: Control = (screen.get(&"_gear") as GearPanel).view_of({"grid": grid})
	return view.get_global_rect().position + (Vector2(int(placed["x"]), int(placed["y"])) + Vector2(0.5, 0.5)) * GearPanel.CELL


func _left_press(at: Vector2) -> InputEventMouseButton:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.global_position = at
	press.position = at
	return press
