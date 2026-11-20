class_name LootItem
extends Node3D
## An item lying on the ground. Created by the server and, through the inventory module's
## spawner, on every client. Shows a plain box sized like the item in the grid until
## another module gives it a better look (`set_visual`: the weapons module puts the part's
## own mesh on it), and its name close up.

const CELL_METRES := 0.09
const LABEL_RANGE := 5.0
## Metres between the top of the item and its name.
const LABEL_GAP := 0.12

var item := ""
var short_name := ""
var colour := Color(0.4, 0.4, 0.4)
var cells := Vector2i.ONE

var _box: MeshInstance3D
var _dressed := false
## Holds the box or the model, scaled up for the ground (#424).
var _look := Node3D.new()
var _label: Label3D
var _targeted := false

static var _outline: StandardMaterial3D


func _ready() -> void:
	add_to_group(&"loot")
	_look.name = "Look"
	add_child(_look)
	_box = MeshInstance3D.new()
	# A model may already be on it (it is dressed before entering the tree).
	_box.visible = not _dressed
	var mesh := BoxMesh.new()
	mesh.size = Vector3(cells.x * CELL_METRES, 0.05, cells.y * CELL_METRES)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour.darkened(0.2)
	mat.roughness = 0.8
	mesh.material = mat
	_box.mesh = mesh
	_box.position.y = 0.025
	_look.add_child(_box)
	var label := Label3D.new()
	_label = label
	label.text = short_name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.pixel_size = 0.002
	label.outline_size = 10
	label.position.y = 0.22
	label.visibility_range_end = LABEL_RANGE
	add_child(label)
	_fit()


## Replaces the plain box with a model of the real thing, lying on the ground.
func set_visual(node: Node3D) -> void:
	_dressed = true
	if _box != null:
		_box.visible = false
	_look.add_child(node)
	if is_inside_tree():
		_fit()


## Lights the item up while it is the one a press of interact would pick up (client only).
func set_targeted(on: bool) -> void:
	if on == _targeted:
		return
	_targeted = on
	if _outline == null:
		# A soft glow added over the model: a grown shell (an outline) splits apart on the
		# flat-shaded voxel models and reads as a hollow, flickering ring.
		_outline = StandardMaterial3D.new()
		_outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_outline.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_outline.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_outline.albedo_color = PickupRules.outline_colour()
	for mesh: Node in _look.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_overlay = _outline if on else null


## How much bigger the look is drawn than the item's real size.
func ground_scale() -> float:
	return _look.scale.x


## Bigger than in the hand, and never smaller than `min_size` across, so small things
## (ammo, a medkit) still show in grass; laid flat if it would stand on end, resting on the
## ground by its lowest point, with its name just above it.
func _fit() -> void:
	_look.transform = Transform3D.IDENTITY
	var box := _bounds()
	if box.size == Vector3.ZERO:
		return
	var factor := maxf(PickupRules.number("ground_scale"), PickupRules.number("min_size") / box.get_longest_axis_size())
	# A magazine or a stock modelled upright would stand like a post: lie it on its side.
	if box.size.y > maxf(box.size.x, box.size.z):
		_look.rotation.z = PI / 2.0
	_look.scale = Vector3.ONE * factor
	box = _bounds()
	_look.position.y -= box.position.y
	if _label != null:
		_label.position.y = box.size.y + LABEL_GAP


## The visible meshes' box in this item's own space, as the look is placed now.
func _bounds() -> AABB:
	var box := AABB()
	var first := true
	var to_item := global_transform.affine_inverse() if is_inside_tree() else Transform3D.IDENTITY
	for node: Node in _look.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not mesh.visible:
			continue
		var placed := to_item * mesh.global_transform if mesh.is_inside_tree() else _look.transform * mesh.transform
		var part := placed * mesh.mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box
