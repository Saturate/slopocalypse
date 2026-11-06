extends Node
## Equips spawned players with a rifle: the first-person weapon at the camera, the same rifle
## in the third-person body's hands, and, for the local player, shot feedback.

const RIFLE := "res://modules/weapons/scenes/rifle.tscn"

static var _held_mesh: ArrayMesh

var _charge_spawner := MultiplayerSpawner.new()
var _charges_placed := 0


func _ready() -> void:
	# Placed charges are created by the server and replicated, so everyone sees them blink.
	_charge_spawner.name = "ChargeSpawner"
	_charge_spawner.spawn_path = NodePath("..")
	_charge_spawner.spawn_function = _make_charge
	add_child(_charge_spawner)
	EventBus.subscribe(&"player.spawned", _on_player_spawned)
	if DisplayServer.get_name() != "headless":
		var effects := ExplosionEffects.new()
		effects.name = "ExplosionEffects"
		add_child(effects)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"player.spawned", _on_player_spawned)


func _on_player_spawned(p: Dictionary) -> void:
	var player: PlayerController = p["player"]
	var rifle: HitscanWeapon = (load(RIFLE) as PackedScene).instantiate()
	rifle.holder = player
	# At the camera, so shots start at the eye and follow the view.
	player.get_node("Head/Camera").add_child(rifle)
	var thrower := ChargeThrower.new()
	thrower.name = "ChargeThrower"
	thrower.holder = player
	thrower.charges_parent = self
	player.add_child(thrower)
	if DisplayServer.get_name() == "headless":
		return
	# What everyone else (and the local player's shadow) sees: the rifle in the body's hands.
	var socket := PlayerBody.weapon_socket(player)
	if socket != null:
		var held := MeshInstance3D.new()
		held.name = "HeldRifle"
		held.mesh = _third_person_mesh()
		socket.add_child(held)
	if p.get("local", false):
		var feedback := ShotFeedback.new()
		feedback.name = "ShotFeedback"
		feedback.local_player = player
		add_child(feedback)


## Server only, called by ChargeThrower.
func spawn_charge(at: Vector3, stats: Dictionary) -> DemolitionCharge:
	_charges_placed += 1
	return _charge_spawner.spawn({"index": _charges_placed, "position": at, "stats": stats})


## Runs on the server and, through the spawner, on every client.
func _make_charge(data: Variant) -> Node:
	var info: Dictionary = data
	var charge := DemolitionCharge.new()
	charge.name = "Charge%d" % int(info["index"])
	charge.stats = info["stats"]
	charge.position = info["position"]
	return charge


## Built once and shared by every player's held rifle.
static func _third_person_mesh() -> ArrayMesh:
	if _held_mesh == null:
		_held_mesh = RifleMesh.rifle()
	return _held_mesh
