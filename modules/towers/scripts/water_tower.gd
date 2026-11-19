class_name WaterTower
extends StaticBody3D
## A voxel water tower (VoxWaterTower) whose tank leaks where it is shot. The server decides
## the holes (TowersModule); every machine drains the same `WaterTank` from them, so the
## level is never sent. Clients draw a stream from each pouring hole and a puddle spreading
## under the tower.

## Stable across server and clients: towers are numbered as they are placed.
var tower_id := 0
## The `tower` block of towers.json.
var config: Dictionary = {}
var tank := WaterTank.new()

var _model: VoxelModel
var _mesh: VoxelChunkedMesh
var _legs := 7.0
var _radius := 1.6
var _tank_height := 2.6
## Per hole, in order: {point (local), normal (local), stream: CPUParticles3D or null}.
var _holes: Array[Dictionary] = []
var _visual := DisplayServer.get_name() != "headless"
var _redraw_in := 0.0
var _puddle_drawn := 0.0


func _ready() -> void:
	collision_layer = PhysicsLayers.SOLID
	_legs = float(config.get("height", 7.0))
	_radius = float(config.get("radius", 1.6))
	_tank_height = float(config.get("tank", 2.6))
	tank.area = PI * _radius * _radius
	tank.height = _tank_height
	tank.level = _tank_height * float(config.get("fill", 0.9))
	tank.flow = float(config.get("flow", 0.05))
	tank.max_holes = int(config.get("max_holes", 24))
	_model = VoxWaterTower.new().build({"seed": tower_id + 1, "height": _legs, "radius": _radius, "tank": _tank_height})
	var leg := _radius * 0.7
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var box := BoxShape3D.new()
			box.size = Vector3(VoxWaterTower.LEG, _legs, VoxWaterTower.LEG)
			_add_shape(box, Vector3(float(sx) * leg, _legs / 2.0, float(sz) * leg))
	var cylinder := CylinderShape3D.new()
	cylinder.radius = _radius
	cylinder.height = _tank_height
	_add_shape(cylinder, Vector3(0.0, _legs + _tank_height / 2.0, 0.0))
	if not _visual:
		return
	_mesh = VoxelChunkedMesh.new()
	# Shot full of holes: drawn a chunk at a time so each hole stays cheap.
	_mesh.editable = true
	_mesh.name = "Mesh"
	_mesh.model = _model
	add_child(_mesh)
	_mesh.refresh()


func _add_shape(shape: Shape3D, at: Vector3) -> void:
	var node := CollisionShape3D.new()
	node.shape = shape
	node.position = at
	add_child(node)


## Where a round that struck at `point` (world) holed the tank: {height above the tank floor,
## point and normal (local)}, or empty if it struck something else (a leg, the roof).
func tank_hit(point: Vector3) -> Dictionary:
	var local := to_local(point)
	var flat := Vector2(local.x, local.z)
	var up := local.y - _legs
	if up < 0.05 or up > _tank_height - 0.05 or absf(flat.length() - _radius) > 0.3:
		return {}
	var normal := Vector3(flat.x, 0.0, flat.y).normalized()
	return {"height": up, "point": Vector3(flat.normalized().x * _radius, local.y, flat.normalized().y * _radius), "normal": normal}


## Everywhere: a hole at `point` (local) facing `normal`, made `age` seconds ago.
func add_hole(point: Vector3, normal: Vector3, age := 0.0) -> void:
	tank.add_hole(point.y - _legs, tank.clock - age)
	_holes.append({"point": point, "normal": normal, "stream": null})
	if _model != null:
		var v := 0.1
		_model.carve_box(point - normal * v * 1.5 - Vector3.ONE * v * 0.5, point + Vector3.ONE * v * 0.5)
		if _mesh != null:
			_mesh.refresh()


## A late joiner: the holes so far with their ages, the level stepped to where it is now.
func catch_up(holes: Array) -> void:
	var given: Array = []
	for h: Dictionary in holes:
		var point: Vector3 = h["point"]
		given.append({"height": point.y - _legs, "age": float(h["age"])})
		_holes.append({"point": point, "normal": h["normal"], "stream": null})
		if _model != null:
			_model.carve_box(point - Vector3.ONE * 0.1, point + Vector3.ONE * 0.05)
	tank.catch_up(given)
	if _mesh != null:
		_mesh.refresh()


## For someone joining: every hole with its point, normal and age.
func snapshot() -> Array:
	var out: Array = []
	var ages := tank.ages()
	for i in _holes.size():
		out.append({"point": _holes[i]["point"], "normal": _holes[i]["normal"], "age": float(ages[i]["age"])})
	return out


func level() -> float:
	return tank.level


func _process(delta: float) -> void:
	if _holes.is_empty():
		return
	var t := Prof.start()
	tank.advance(delta)
	if _visual:
		_redraw_in -= delta
		if _redraw_in <= 0.0:
			_redraw_in = 0.25
			_update_streams()
			_update_puddle()
	Prof.stop(&"towers/tank", t)


func _update_streams() -> void:
	var open := tank.pouring()
	var view := get_tree().get_first_node_in_group(&"water_view")
	for i in _holes.size():
		var hole := _holes[i]
		var depth := tank.level - (float((hole["point"] as Vector3).y) - _legs)
		var pours := open.has(tank.holes[i]) and depth > 0.0
		var stream := hole["stream"] as CPUParticles3D
		if not pours:
			if stream != null:
				stream.emitting = false
			continue
		# Water leaves a hole at about sqrt(2 g depth); a little less reads better at this size.
		var speed := sqrt(2.0 * 9.8 * depth) * 0.8
		if stream == null:
			stream = _stream(hole["point"], hole["normal"])
			hole["stream"] = stream
		stream.emitting = true
		stream.initial_velocity_min = speed * 0.85
		stream.initial_velocity_max = speed
		if view != null:
			var from := global_transform * (hole["point"] as Vector3)
			var fall := sqrt(2.0 * maxf(from.y - global_position.y, 0.1) / 9.8)
			var out := global_basis * (hole["normal"] as Vector3) * speed * fall
			view.call(&"add_ripple", Vector3(from.x + out.x, global_position.y, from.z + out.z), 0.35)


func _stream(point: Vector3, normal: Vector3) -> CPUParticles3D:
	var s := CPUParticles3D.new()
	s.amount = 260
	# Gone as they reach the ground (particles here don't collide): the time to fall that far.
	s.lifetime = sqrt(2.0 * maxf(point.y, 0.5) / 9.8)
	s.direction = normal
	s.spread = 4.0
	s.gravity = Vector3(0, -9.8, 0)
	s.local_coords = false
	var drop := BoxMesh.new()
	drop.size = Vector3(0.1, 0.24, 0.1)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.7, 0.85, 0.9)
	material.emission_enabled = true
	material.emission = Color(0.25, 0.32, 0.35)
	material.roughness = 0.15
	drop.material = material
	s.mesh = drop
	s.position = point + normal * 0.05
	add_child(s)
	return s


func _update_puddle() -> void:
	var radius := WaterTank.puddle_radius(tank.poured, float(config.get("puddle_film", 0.05)), float(config.get("max_puddle_radius", 6.0)))
	if radius - _puddle_drawn < 0.25:
		return
	var view := get_tree().get_first_node_in_group(&"water_view")
	var ground := get_tree().get_first_node_in_group(&"ground")
	if view == null:
		return
	_puddle_drawn = radius
	var base := global_position.y
	var height_at := func(x: float, z: float) -> float:
		return float(ground.call(&"surface_height", x, z)) if ground != null and ground.has_method(&"surface_height") else base
	view.call(&"drape", "tower%d" % tower_id, global_position, radius, height_at)


func puddle_radius() -> float:
	return _puddle_drawn
