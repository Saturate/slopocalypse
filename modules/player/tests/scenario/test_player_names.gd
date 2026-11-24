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
	Net._identities.erase(PEER + 1)


func _bodies_of(peer: int) -> int:
	return (_module.call(&"players") as Array).filter(func(p: Node) -> bool: return int(p.get_meta(&"peer_id", 0)) == peer).size()


# The save smoke's returning player connected while the server's world loaded and said who
# they were just after it was ready: a body spawned then had no name, so persistence never
# put them back where they left (#552).
func test_a_peer_still_connecting_when_the_world_is_ready_waits_for_their_name() -> void:
	EventBus.publish(&"world.ready", {"spawn": Vector3(0, 1, 0)})
	Net._identities[PEER] = {"name": "Ana", "key": "test"}
	_module.call(&"server_spawn_joined", PackedInt32Array([PEER, PEER + 1]))
	assert_int(_bodies_of(PEER)).is_equal(1)
	assert_int(_bodies_of(PEER + 1)).is_equal(0)
	Net._identities[PEER + 1] = {"name": "Bo", "key": "test"}
	_module.call(&"_on_peer_joined", PEER + 1)
	assert_int(_bodies_of(PEER + 1)).is_equal(1)
	var bo: Array = (_module.call(&"players") as Array).filter(func(p: Node) -> bool: return int(p.get_meta(&"peer_id", 0)) == PEER + 1)
	assert_str(str((bo[0] as Node).get_meta(&"player_name", ""))).is_equal("Bo")


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
