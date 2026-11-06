extends Node3D
## Capture setup: every tree variant in a row on flat ground, at its smallest and largest
## scale, for judging the ugly extremes.

var _camera := Camera3D.new()


func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-40), deg_to_rad(30), 0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.7, 0.78)
	env.environment.ambient_light_color = Color(0.6, 0.62, 0.6)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	add_child(env)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 60)
	ground.mesh = plane
	add_child(ground)
	var variants: Array = SceneryScatter.TREE_VARIANTS
	for i in variants.size():
		var spec: Array = variants[i]
		var mesh := PineTreeMesh.build(spec[0], spec[1], spec[2])
		for row in 2:
			var tree := MeshInstance3D.new()
			tree.mesh = mesh
			var s := SceneryScatter.TREE_SCALE.x if row == 0 else minf(SceneryScatter.TREE_SCALE.y, SceneryScatter.TREE_MAX_HEIGHT / float(spec[1]))
			tree.scale = Vector3.ONE * s
			tree.position = Vector3(-54 + i * 12, 0, -row * 14)
			add_child(tree)
			var label := Label3D.new()
			label.text = "%d %s x%.2f" % [i, spec[2], s]
			label.font_size = 64
			label.position = tree.position + Vector3(0, -0.5, 4)
			label.rotation.x = -PI / 2.0
			add_child(label)
	add_child(_camera)
	_camera.current = true
	_camera.fov = 60
	_camera.global_transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-12), 0, 0)), Vector3(0, 12, 42))
