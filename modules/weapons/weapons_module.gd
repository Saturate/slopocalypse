extends Node
## Equips spawned players with a rifle and, on clients, shows shot feedback.

const RIFLE := "res://modules/weapons/scenes/rifle.tscn"


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
	if p.get("local", false) and DisplayServer.get_name() != "headless":
		var feedback := ShotFeedback.new()
		feedback.name = "ShotFeedback"
		feedback.local_player = player
		add_child(feedback)
