class_name FirstPersonLayer
extends Node
## Client, your own body in first person: keeps the arms and everything held in them (the
## gun, and whatever is mounted on it later) on RenderLayers.FIRST_PERSON and no other
## layer, so a light at your own chest can leave them out (docs/decisions/0018). Added by
## PlayerBody.first_person() as a child of the body.

const ARMS := "Skeleton/Arms"
const HELD := "Skeleton/WeaponAttachment"

var _body: Node


func _ready() -> void:
	_body = get_parent()
	for node in _body.find_children("*", "GeometryInstance3D", true, false):
		if covers(node):
			(node as GeometryInstance3D).layers = RenderLayers.FIRST_PERSON
	get_tree().node_added.connect(_on_node_added)


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


## Whether `node` is the arms or under what they hold.
func covers(node: Node) -> bool:
	if _body == null:
		return false
	if node == _body.get_node_or_null(ARMS):
		return true
	var held := _body.get_node_or_null(HELD)
	return held != null and held.is_ancestor_of(node)


func _on_node_added(node: Node) -> void:
	if node is GeometryInstance3D and covers(node):
		# Deferred, after whatever else moves new meshes between layers as they enter the
		# tree (gore keeps bodies off the layer blood paints).
		_tag.call_deferred(node)


func _tag(node: Node) -> void:
	if is_instance_valid(node) and covers(node):
		(node as GeometryInstance3D).layers = RenderLayers.FIRST_PERSON
