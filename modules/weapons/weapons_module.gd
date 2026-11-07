extends Node
## Equips spawned players with a rifle: its logic at the camera (shots follow the aim) and
## its one visible model in the body's hands, which the owner sees in first person and
## everyone else in third. Adds shot effects for all shots and the HUD for the local player.

const RIFLE := "res://modules/weapons/scenes/rifle.tscn"
## Muzzle of RifleMesh.rifle(), in the held rifle's space.
const MUZZLE := Vector3(0.0, 0.04, -0.64)

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
		var shots := ShotEffects.new()
		shots.name = "ShotEffects"
		add_child(shots)


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
	var socket := PlayerBody.weapon_socket(player)
	if socket != null:
		var held := MeshInstance3D.new()
		held.name = "HeldRifle"
		held.mesh = _held_mesh_shared()
		var muzzle := Marker3D.new()
		muzzle.name = "Muzzle"
		muzzle.position = MUZZLE
		held.add_child(muzzle)
		socket.add_child(held)
	if DisplayServer.get_name() == "headless":
		return
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
static func _held_mesh_shared() -> ArrayMesh:
	if _held_mesh == null:
		_held_mesh = RifleMesh.rifle()
	return _held_mesh
