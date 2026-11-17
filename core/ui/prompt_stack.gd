class_name PromptStack
extends CanvasLayer
## The one place under the crosshair for "press a key to do something" prompts. Modules
## set a line by id each frame they have one and clear it when they don't; lines stack in
## `order` instead of each module guessing an offset and landing on top of another.
## Hidden while a screen is open.

## Below the crosshair, at the 1600x900 base.
const OFFSET_Y := 56.0

var _column: VBoxContainer
var _lines: Dictionary[StringName, KeyHint] = {}
var _order: Dictionary[StringName, int] = {}


## The scene's prompt stack, made on first use. It lives under the current scene, so
## leaving a session (which reloads the scene) takes it and its lines away.
static func of(tree: SceneTree) -> PromptStack:
	var scene := tree.current_scene if tree.current_scene != null else tree.root
	if scene.has_meta(&"prompt_stack"):
		var kept: Variant = scene.get_meta(&"prompt_stack")
		if is_instance_valid(kept):
			return kept as PromptStack
	var found := PromptStack.new()
	found.name = "PromptStack"
	scene.set_meta(&"prompt_stack", found)
	# Deferred: the scene may still be adding its own children when a prompt first asks.
	scene.add_child.call_deferred(found)
	return found


func _init() -> void:
	layer = UiLayers.PROMPTS
	_column = VBoxContainer.new()
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.alignment = BoxContainer.ALIGNMENT_BEGIN
	_column.add_theme_constant_override(&"separation", 6)
	_column.anchor_left = 0.5
	_column.anchor_right = 0.5
	_column.anchor_top = 0.5
	_column.anchor_bottom = 0.5
	_column.offset_top = OFFSET_Y
	_column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_column)


## Shows (or updates) the line `id`. `action` empty for text alone.
func set_line(id: StringName, action: StringName, what: String, order := 0) -> void:
	var line: KeyHint = _lines.get(id)
	if line == null:
		line = KeyHint.new(action, what)
		# Rows start at the same x so the key caps line up; the column as a whole is centred.
		line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_lines[id] = line
		_order[id] = order
		_column.add_child(line)
		_sort()
	elif line.action != action or line.text != what:
		line.action = action
		line.text = what
		line.refresh()


func clear_line(id: StringName) -> void:
	var line: KeyHint = _lines.get(id)
	if line == null:
		return
	_lines.erase(id)
	_order.erase(id)
	line.queue_free()


func has_line(id: StringName) -> bool:
	return _lines.has(id)


func line_text(id: StringName) -> String:
	var line: KeyHint = _lines.get(id)
	return line.text if line != null else ""


func _process(_delta: float) -> void:
	_column.visible = not UiStack.is_blocking()


func _sort() -> void:
	var ids := _lines.keys()
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return _order[a] < _order[b])
	for i in ids.size():
		_column.move_child(_lines[ids[i]], i)
