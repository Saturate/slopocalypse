extends Node
## Equips spawned players with a rifle: the first-person weapon at the camera, the same rifle
## in the third-person body's hands, and, for the local player, shot feedback.

const RIFLE := "res://modules/weapons/scenes/rifle.tscn"

static var _held_mesh: ArrayMesh


func _ready() -> void:
	EventBus.subscribe(&"player.spawned", _on_player_spawned)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"player.spawned", _on_player_spawned)


func _on_player_spawned(p: Dictionary) -> void:
	var player: PlayerController = p["player"]
	var rifle: HitscanWeapon = (load(RIFLE) as PackedScene).instantiate()
	rifle.holder = player
	# At the camera, so shots start at the eye and follow the view.
	player.get_node("Head/Camera").add_child(rifle)
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


## Built once and shared by every player's held rifle.
static func _third_person_mesh() -> ArrayMesh:
	if _held_mesh == null:
		_held_mesh = RifleMesh.rifle()
	return _held_mesh
