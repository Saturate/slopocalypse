class_name ItemIcons
extends Node
## Client only: a picture of each item, rendered once from its 3D model in an off-screen
## view and cached, for the inventory tiles. The model faces the camera with its broadest
## side, its long axis along the tile's long side, a little turned so it reads as 3D. Asking
## for an icon not rendered yet returns null and queues it; `icon_ready` fires when it is.

signal icon_ready(item: String)

## Pixels per inventory cell in a rendered icon.
const CELL_PIXELS := 64
const MARGIN := 1.12
const TILT := Vector3(0.18, -0.3, 0.0)
const LIGHT_ENERGY := 2.2
const FILL_ENERGY := 0.9

## Item id -> Node3D (a fresh model for that item, or null when there is none).
var model_for: Callable
## Item id -> Vector2i cells (w, h) of the item upright.
var cells_for: Callable

var _icons: Dictionary[String, Texture2D] = {}
var _queue: Array[String] = []
var _busy := false
var _viewport: SubViewport
var _pivot: Node3D
var _camera: Camera3D


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.msaa_3d = Viewport.MSAA_4X
	add_child(_viewport)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.76, 0.8)
	env.environment.ambient_light_energy = 1.2
	_viewport.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0.0)
	sun.light_energy = LIGHT_ENERGY
	_viewport.add_child(sun)
	# A softer light from the front-left so dark parts (black gun metal) still show their shape.
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(-0.3, -0.9, 0.0)
	fill.light_energy = FILL_ENERGY
	_viewport.add_child(fill)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.position = Vector3(0, 0, 10)
	_camera.current = true
	_viewport.add_child(_camera)
	_pivot = Node3D.new()
	_viewport.add_child(_pivot)


## The icon for `item`, or null (queued) while it is being rendered or if it has no model.
func icon(item: String) -> Texture2D:
	if _icons.has(item):
		return _icons[item]
	if not _queue.has(item):
		_queue.append(item)
	return null


func _process(_delta: float) -> void:
	if _busy or _queue.is_empty():
		return
	_render(_queue.pop_front())


func _render(item: String) -> void:
	_busy = true
	for child in _pivot.get_children():
		child.queue_free()
	var model: Node3D = model_for.call(item) if model_for.is_valid() else null
	if model == null:
		_icons[item] = null
		_busy = false
		return
	var cells: Vector2i = cells_for.call(item) if cells_for.is_valid() else Vector2i.ONE
	_viewport.size = Vector2i(maxi(cells.x, 1), maxi(cells.y, 1)) * CELL_PIXELS
	var holder := Node3D.new()
	_pivot.add_child(holder)
	holder.add_child(model)
	_frame(holder, model, cells)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var image := _viewport.get_texture().get_image()
	_icons[item] = ImageTexture.create_from_image(image)
	holder.queue_free()
	_busy = false
	icon_ready.emit(item)


## Turns the model for its tile, tilts it a little, then sizes the camera to fit. In a square
## tile it stands upright (gear: a pack, a medkit) with its broader side to the camera, front
## (-Z) first. In a long tile it lies along the tile's long side, broadest face to the
## camera, front (a muzzle) pointing right or up.
func _frame(holder: Node3D, model: Node3D, cells: Vector2i) -> void:
	var box := _bounds(model, Transform3D.IDENTITY)
	model.position = -box.get_center()
	var size := box.size
	var turn: Basis
	if cells.x == cells.y and size.y > minf(size.x, size.z):
		if size.z <= size.x:
			# Front to the camera: turned half round.
			turn = Basis(Vector3.LEFT, Vector3.UP, Vector3.FORWARD)
		else:
			# Side on, front to the right.
			turn = Basis(Vector3.BACK, Vector3.UP, Vector3.LEFT)
	else:
		var order := [0, 1, 2]
		order.sort_custom(func(a: int, b: int) -> bool: return size[a] < size[b])
		var facing: int = order[0]
		var longest: int = order[2]
		var wide := cells.x >= cells.y
		# Columns: where the model's x, y, z go in view space (x right, y up, z to the camera).
		var cols: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
		cols[facing] = Vector3.FORWARD
		var along := Vector3.RIGHT if wide else Vector3.UP
		# The front (-Z) leads: model +Z goes the other way.
		cols[longest] = -along if longest == 2 else along
		cols[order[1]] = Vector3.UP if wide else Vector3.RIGHT
		# A mirror image is no rotation: show the other face instead, keeping its top up.
		if Basis(cols[0], cols[1], cols[2]).determinant() < 0.0:
			cols[facing] = -cols[facing]
		turn = Basis(cols[0], cols[1], cols[2])
	holder.basis = Basis.from_euler(TILT) * turn
	var seen := _bounds(holder, holder.transform)
	var aspect := float(cells.x) / float(maxi(cells.y, 1))
	_camera.size = maxf(seen.size.y, seen.size.x / aspect) * MARGIN
	_camera.position = Vector3(seen.get_center().x, seen.get_center().y, seen.end.z + 5.0)


## The combined bounds of every mesh under `node`, in `node`'s parent space via `xform`.
func _bounds(node: Node3D, xform: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	for mesh in _meshes(node):
		var local := xform * _relative(mesh, node)
		var box := local * mesh.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out if not first else AABB(Vector3(-0.05, -0.05, -0.05), Vector3(0.1, 0.1, 0.1))


func _relative(child: Node3D, ancestor: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = child
	while n != null and n != ancestor:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		out.append_array(_meshes(child))
	return out
