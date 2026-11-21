extends GdUnitTestSuite
## A player's name rides along with their spawn, so every copy of them (on every client)
## knows it: the compass labels other players by it (#455).

const MODULE := "res://modules/player/player_module.gd"
const PEER := 77

var _module: Node


func before_test() -> void:
	_module = auto_free((load(MODULE) as GDScript).new())
	add_child(_module)


func after_test() -> void:
	Net._identities.erase(PEER)


func test_the_server_sends_the_name_with_the_spawn() -> void:
	EventBus.publish(&"world.ready", {"spawn": Vector3(0, 1, 0)})
	Net._identities[PEER] = {"name": "Ana", "key": "test"}
	_module.call(&"_server_spawn", PEER)
	var ana: Array = (_module.call(&"players") as Array).filter(func(p: Node) -> bool: return int(p.get_meta(&"peer_id", 0)) == PEER)
	assert_int(ana.size()).is_equal(1)
	assert_str(str((ana[0] as Node).get_meta(&"player_name", ""))).is_equal("Ana")


func test_a_copy_spawned_from_the_data_carries_the_name() -> void:
	var copy: Node = _module.call(&"_spawn_player", {"peer": PEER + 1, "position": Vector3.ZERO, "name": "Ranger"})
	auto_free(copy)
	assert_str(str(copy.get_meta(&"player_name", ""))).is_equal("Ranger")
