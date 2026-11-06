extends SceneTree
## Builds modules/player/scenes/player_body.tscn: a chunky low-poly soldier made of bevelled
## parts on joint pivots. Pivots use standard humanoid bone names (Hips, Spine, Chest, Head,
## UpperLeg_L ...) so a rigged model from the art teammate can replace this later.
## Feet at the origin, facing -Z, 1.8 m tall.

const OUT := "res://modules/player/scenes/player_body.tscn"

const CAMO := Color(0.33, 0.37, 0.26)
const CAMO_DARK := Color(0.26, 0.29, 0.2)
const VEST := Color(0.45, 0.42, 0.3)
const POUCH := Color(0.38, 0.35, 0.24)
const SKIN := Color(0.78, 0.6, 0.47)
const HELMET := Color(0.3, 0.33, 0.24)
const DARK := Color(0.12, 0.12, 0.12)
const BOOT := Color(0.2, 0.16, 0.12)
const GLOVE := Color(0.16, 0.15, 0.14)


func _initialize() -> void:
	var root := Node3D.new()
	root.name = "PlayerBody"

	# Chunky proportions: shorter, sturdier legs, a big torso and an oversized helmet read
	# well at distance in a low-poly shooter.
	var hips := _pivot("Hips", root, Vector3(0, 0.86, 0))
	_part("Pelvis", hips, func(st: SurfaceTool) -> void:
		LowPoly.chamfer_box(st, Vector3(0.4, 0.2, 0.25), 0.04, _at(Vector3(0, -0.02, 0)), CAMO_DARK)
		LowPoly.chamfer_box(st, Vector3(0.42, 0.06, 0.27), 0.015, _at(Vector3(0, 0.07, 0)), DARK)
		LowPoly.chamfer_box(st, Vector3(0.1, 0.12, 0.08), 0.02, _at(Vector3(0.2, 0.0, 0.02)), POUCH))

	var spine := _pivot("Spine", hips, Vector3(0, 0.09, 0))
	var chest := _pivot("Chest", spine, Vector3(0, 0.18, 0))
	_part("Torso", chest, func(st: SurfaceTool) -> void:
		LowPoly.chamfer_box(st, Vector3(0.46, 0.48, 0.27), 0.06, _at(Vector3(0, 0.1, 0)), CAMO)
		# Plate carrier and pouches give the silhouette its soldier read.
		LowPoly.chamfer_box(st, Vector3(0.52, 0.38, 0.34), 0.05, _at(Vector3(0, 0.1, 0)), VEST)
		for x in [-0.15, 0.0, 0.15]:
			LowPoly.chamfer_box(st, Vector3(0.12, 0.14, 0.07), 0.02, _at(Vector3(x, -0.01, -0.2)), POUCH)
		LowPoly.chamfer_box(st, Vector3(0.36, 0.14, 0.1), 0.03, _at(Vector3(0, 0.2, 0.19)), POUCH)
		LowPoly.chamfer_box(st, Vector3(0.14, 0.08, 0.12), 0.02, _at(Vector3(0, 0.33, 0)), CAMO_DARK))

	var head := _pivot("Head", chest, Vector3(0, 0.38, 0))
	_part("HeadMesh", head, func(st: SurfaceTool) -> void:
		LowPoly.chamfer_box(st, Vector3(0.22, 0.22, 0.23), 0.06, _at(Vector3(0, 0.1, 0)), SKIN)
		# Helmet: shell, brim and side shells so it reads as a helmet, not a cap.
		LowPoly.chamfer_box(st, Vector3(0.3, 0.16, 0.32), 0.07, _at(Vector3(0, 0.22, 0.01)), HELMET)
		LowPoly.chamfer_box(st, Vector3(0.33, 0.035, 0.36), 0.012, _at(Vector3(0, 0.16, 0.0)), HELMET.darkened(0.15))
		for x in [-0.155, 0.155]:
			LowPoly.chamfer_box(st, Vector3(0.04, 0.13, 0.22), 0.015, _at(Vector3(x, 0.14, 0.02)), HELMET.darkened(0.1))
		LowPoly.chamfer_box(st, Vector3(0.2, 0.05, 0.03), 0.012, _at(Vector3(0, 0.12, -0.12)), DARK)
		LowPoly.chamfer_box(st, Vector3(0.09, 0.03, 0.03), 0.01, _at(Vector3(0, 0.03, -0.115)), SKIN.darkened(0.2)))

	# Arms are posed holding a rifle across the chest; they move with the chest when aiming.
	var grip := Vector3(0.12, 0.02, -0.2)
	var fore := Vector3(-0.02, 0.1, -0.46)
	_part("Arms", chest, func(st: SurfaceTool) -> void:
		var r_shoulder := Vector3(0.28, 0.27, 0)
		var r_elbow := Vector3(0.3, 0.0, -0.06)
		_limb(st, r_shoulder, r_elbow, 0.13, CAMO)
		_limb(st, r_elbow, grip, 0.115, CAMO_DARK)
		LowPoly.chamfer_box(st, Vector3(0.1, 0.11, 0.11), 0.03, _at(grip), GLOVE)
		var l_shoulder := Vector3(-0.28, 0.27, 0)
		var l_elbow := Vector3(-0.24, 0.04, -0.26)
		_limb(st, l_shoulder, l_elbow, 0.13, CAMO)
		_limb(st, l_elbow, fore, 0.115, CAMO_DARK)
		LowPoly.chamfer_box(st, Vector3(0.1, 0.08, 0.12), 0.03, _at(fore), GLOVE)
		# Shoulder pads round off the joint.
		LowPoly.chamfer_box(st, Vector3(0.16, 0.15, 0.17), 0.05, _at(r_shoulder + Vector3(0.02, 0, 0)), CAMO_DARK)
		LowPoly.chamfer_box(st, Vector3(0.16, 0.15, 0.17), 0.05, _at(l_shoulder - Vector3(0.02, 0, 0)), CAMO_DARK))

	# Where the weapons module mounts the third-person rifle: grip in the right hand.
	var socket := Marker3D.new()
	socket.name = "WeaponSocket"
	socket.position = grip + Vector3(-0.12, 0.07, -0.12)
	chest.add_child(socket)

	for side in [["L", -1.0], ["R", 1.0]]:
		var upper := _pivot("UpperLeg_" + side[0], hips, Vector3(side[1] * 0.11, -0.07, 0))
		_part("Thigh", upper, func(st: SurfaceTool) -> void:
			LowPoly.chamfer_box(st, Vector3(0.19, 0.4, 0.21), 0.05, _at(Vector3(0, -0.18, 0)), CAMO)
			LowPoly.chamfer_box(st, Vector3(0.08, 0.13, 0.1), 0.02, _at(Vector3(side[1] * 0.1, -0.18, 0)), POUCH))
		var lower := _pivot("LowerLeg_" + side[0], upper, Vector3(0, -0.38, 0))
		_part("Shin", lower, func(st: SurfaceTool) -> void:
			LowPoly.chamfer_box(st, Vector3(0.17, 0.33, 0.19), 0.05, _at(Vector3(0, -0.15, 0)), CAMO_DARK)
			LowPoly.chamfer_box(st, Vector3(0.18, 0.11, 0.07), 0.025, _at(Vector3(0, 0.0, -0.1)), DARK)
			LowPoly.chamfer_box(st, Vector3(0.19, 0.13, 0.31), 0.045, _at(Vector3(0, -0.34, -0.05)), BOOT))

	var result := SceneBuilder.pack_and_save(root, OUT)
	root.free()
	if result.error != OK:
		push_error(result.message)
		quit(1)
		return
	quit(0)


func _at(pos: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY, pos)


func _pivot(pivot_name: String, parent: Node3D, pos: Vector3) -> Node3D:
	var p := Node3D.new()
	p.name = pivot_name
	p.position = pos
	parent.add_child(p)
	return p


func _part(part_name: String, parent: Node3D, build: Callable) -> void:
	var st := LowPoly.begin()
	build.call(st)
	var inst := MeshInstance3D.new()
	inst.name = part_name
	inst.mesh = LowPoly.finish(st, LowPoly.material(0.85))
	parent.add_child(inst)


func _limb(st: SurfaceTool, from: Vector3, to: Vector3, thickness: float, colour: Color) -> void:
	var dir := to - from
	var up := Vector3.UP if absf(dir.normalized().y) < 0.95 else Vector3.FORWARD
	var basis := Basis.looking_at(dir.normalized(), up)
	LowPoly.chamfer_box(st, Vector3(thickness, thickness, dir.length() + thickness * 0.5), thickness * 0.3, Transform3D(basis, from + dir * 0.5), colour)
