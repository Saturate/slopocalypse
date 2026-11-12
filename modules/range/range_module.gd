extends Node
## The test range: `--range` (or "Test range" in the main menu) starts a solo game that rides
## straight to a fixed row of buildings, one per material, with no guards and no clock. It's
## for breaking things to see how each material takes it, and for measuring what destruction
## costs (`node tools/bench.ts range-destroy` runs `--bot=range` here). Does nothing without
## the flag.
##
## It's a mission kind the module adds to missions, so buildings break, replicate and reach
## late joiners exactly as on a real run.

const CONFIG := "res://modules/range/data/range.json"
const BOT := "res://modules/range/scripts/range_bot.gd"
const TYPE_ID := "test_range"

var config: Dictionary = {}
var active := false


func _ready() -> void:
	active = Net.session_args().has("--range")
	if not active:
		return
	var data: Variant = Data.load_json(CONFIG)
	if not data is Dictionary or not Data.require(CONFIG, data, {"type": TYPE_DICTIONARY, "mission": TYPE_DICTIONARY, "gifts": TYPE_DICTIONARY, "bot": TYPE_DICTIONARY}):
		active = false
		return
	config = data
	var missions := _missions()
	if missions == null:
		Log.error(&"range", "the test range needs the missions module")
		active = false
		return
	missions.call(&"add_type", TYPE_ID, config["type"])
	EventBus.subscribe(&"player.spawned", _on_player_spawned)


func _exit_tree() -> void:
	if active:
		EventBus.unsubscribe(&"player.spawned", _on_player_spawned)


## The one offer the range runs, rolled the way the board rolls offers so it has every field
## a run expects.
func offer() -> Dictionary:
	var missions := _missions()
	var cfg := {
		"missions": [config["mission"]],
		"types": missions.get(&"config")["types"],
		"offered": 1,
		"codenames": {"first": ["Test"], "second": ["Range"]},
	}
	return (missions.call(&"roll_offers", cfg, 1) as Array)[0]


func _on_player_spawned(p: Dictionary) -> void:
	var player := p.get("player") as Node3D
	if player == null:
		return
	if bool(p.get("local", false)) and _bot_wanted():
		var bot: Node = (load(BOT) as GDScript).new()
		bot.name = "RangeBot"
		bot.set(&"player", player)
		bot.set(&"settings", config["bot"])
		player.add_child(bot)
	if multiplayer.is_server():
		# After the spawn settles: other modules equip and place the player first.
		_server_arrive.call_deferred(player)


## Server: the first arrival starts the run and rides out; anyone later (or back from dying)
## is put at the drop-off. Everyone gets the range's charges.
func _server_arrive(player: Node3D) -> void:
	if not is_instance_valid(player):
		return
	var missions := _missions()
	var peer := int(player.get_meta(&"peer_id", 1))
	if str(missions.get(&"state")) == "home":
		missions.set(&"offers", [offer()])
		missions.call(&"server_choose", peer, 0)
		missions.call(&"server_ride_out")
	else:
		var at: Vector3 = missions.call(&"dropoff_of", missions.get(&"current"))
		EventBus.publish(&"player.move_requested", {"player": player, "position": at + Vector3(-2.0, 0.5, 0.0)})
	var inventory := get_tree().get_first_node_in_group(&"inventory_api")
	if inventory != null:
		var gifts: Dictionary = config["gifts"]
		for item: String in gifts:
			for i in int(gifts[item]):
				inventory.call(&"server_give", peer, item)


func _bot_wanted() -> bool:
	return Net.session_args().has("--bot=range")


func _missions() -> Node:
	return get_tree().get_first_node_in_group(&"missions_api")
