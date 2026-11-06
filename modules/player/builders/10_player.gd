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

	var body_mesh := MeshInstance3D.new()
	body_mesh.name = "BodyMesh"
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.radius = 0.35
	capsule_mesh.height = 1.8
	body_mesh.mesh = capsule_mesh
	body_mesh.position = Vector3(0, 0.9, 0)
	root.add_child(body_mesh)

	var head := Node3D.new()
	head.name = "Head"
	root.add_child(head)
	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.fov = 80.0
	head.add_child(camera)

	var intent := Node.new()
	intent.name = "Intent"
	intent.set_script(load("res://modules/player/scripts/player_intent.gd"))
	root.add_child(intent)

	# Script first, then exported properties, or the values are silently dropped.
	root.set_script(load("res://modules/player/scripts/player_controller.gd"))
	root.set("intent_path", NodePath("Intent"))
	root.set("head_path", NodePath("Head"))
	root.set("shape_path", NodePath("Shape"))

	var result := SceneBuilder.pack_and_save(root, OUT)
	root.free()
	if result.error != OK:
		push_error(result.message)
		quit(1)
		return
	quit(0)
