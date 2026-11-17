@tool
class_name BlockPiece
extends Node3D
## One piece of a hand-made city block in the editor: a voxel generator from the kit, its
## parameters, and which of them the city may vary per placement. Shows the model live.

@export var generator := "VoxShed":
	set(value):
		generator = value
		_refresh()
@export var params: Dictionary = {}:
	set(value):
		params = value
		_refresh()
@export var vary: PackedStringArray = []

var _preview: MeshInstance3D


func _validate_property(property: Dictionary) -> void:
	# A list to pick from instead of typing a class name.
	if property["name"] == "generator":
		property["hint"] = PROPERTY_HINT_ENUM
		property["hint_string"] = ",".join(PackedStringArray(CityBlock.generators().keys()))


func _ready() -> void:
	_refresh()


func _refresh() -> void:
	if not is_inside_tree() or not Engine.is_editor_hint():
		return
	var gen := CityBlock.generators().get(generator) as VoxGenerator
	if gen == null:
		return
	if _preview == null:
		_preview = MeshInstance3D.new()
		# Not owned, so the preview is never saved into the scene.
		add_child(_preview, false, Node.INTERNAL_MODE_FRONT)
	_preview.mesh = VoxGenerator.to_mesh(gen.build(params))
