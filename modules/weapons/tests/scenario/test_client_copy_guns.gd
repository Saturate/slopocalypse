extends GdUnitTestSuite
## On a client, someone else's gun and charges are fired by the server and replayed, so they
## run no logic of their own each tick; your own still do (recoil settles, the trigger is read).

const PLAYER := "res://modules/player/scenes/player.tscn"
const MODULE := "res://modules/weapons/weapons_module.gd"

var _client: Node
var _peer: ENetMultiplayerPeer
var _module: Node
var _id := 40


func before_test() -> void:
	_client = Node.new()
	_client.name = "Client"
	add_child(_client)
	# A client that never reaches a server is still a client: not the server, never local peer 1.
	_peer = ENetMultiplayerPeer.new()
	# Nothing listens on port 1, so it never connects, even while another gate runs servers.
	assert_int(_peer.create_client("127.0.0.1", 1)).is_equal(OK)
	var api := SceneMultiplayer.new()
	api.multiplayer_peer = _peer
	get_tree().set_multiplayer(api, _client.get_path())
	_module = (load(MODULE) as GDScript).new()
	_client.add_child(_module)


func after_test() -> void:
	var path := _client.get_path()
	_client.free()
	_peer.close()
	get_tree().set_multiplayer(null, path)


func _spawn(local: bool) -> PlayerController:
	_id += 1
	var player: PlayerController = (load(PLAYER) as PackedScene).instantiate()
	player.name = "P%d" % _id
	player.set_meta(&"peer_id", _id)
	player.add_to_group(&"players")
	_client.add_child(player)
	EventBus.publish(&"player.spawned", {"player": player, "local": local})
	return player


func _gun(player: PlayerController) -> HitscanWeapon:
	return player.get_node("Head/Camera/Weapon_primary") as HitscanWeapon


func test_someone_elses_gun_and_charges_do_not_tick() -> void:
	assert_bool(_client.multiplayer.is_server()).is_false()
	var other := _spawn(false)
	await get_tree().physics_frame
	assert_bool(_gun(other).is_physics_processing()).is_false()
	assert_bool(other.get_node("ChargeThrower").is_physics_processing()).is_false()


func test_your_own_gun_and_charges_still_tick() -> void:
	var own := _spawn(true)
	await get_tree().physics_frame
	assert_bool(_gun(own).is_physics_processing()).is_true()
	assert_bool(own.get_node("ChargeThrower").is_physics_processing()).is_true()
