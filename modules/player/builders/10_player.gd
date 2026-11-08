extends SceneTree
## Builds modules/player/scenes/player.tscn: capsule body, head with camera, intent component.

const OUT := "res://modules/player/scenes/player.tscn"


func _initialize() -> void:
	var root := CharacterBody3D.new()
	root.name = "Player"

	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var capsule := CapsuleShape3D.new()
	# Each player resizes its own capsule when crouching.
	capsule.resource_local_to_scene = true
	shape.shape = capsule
	root.add_child(shape)

	# Built by 05_player_body.gd first; instanced, so its parts stay in their own file.
	var body: Node3D = (load("res://modules/player/scenes/player_body.tscn") as PackedScene).instantiate()
	body.name = "Body"
	root.add_child(body)

	var head := Node3D.new()
	head.name = "Head"
	root.add_child(head)
	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.fov = 80.0
	head.add_child(camera)

	var health := HealthComponent.new()
	health.name = "Health"
	root.add_child(health)

	var intent := Node.new()
	intent.name = "Intent"
	intent.set_script(load("res://modules/player/scripts/player_intent.gd"))
	root.add_child(intent)

	# Script first, then exported properties, or the values are silently dropped.
	root.set_script(load("res://modules/player/scripts/player_controller.gd"))
	root.set("intent_path", NodePath("Intent"))
	root.set("head_path", NodePath("Head"))
	root.set("shape_path", NodePath("Shape"))
	# Server -> clients: where the player is and what they're doing, for remote players'
	# bodies and animation. The local client overrides its own aim every frame.
	root.add_child(NetSync.make([".:position", ".:rotation", "Head:rotation", ".:velocity"], [".:mode", "Intent:crouch", "Intent:lean", "Intent:aim", "Intent:weapon_slot", "Health:health"]))

	var result := SceneBuilder.pack_and_save(root, OUT)
	root.free()
	if result.error != OK:
		push_error(result.message)
		quit(1)
		return
	quit(0)
