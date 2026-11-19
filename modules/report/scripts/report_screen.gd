class_name ReportScreen
extends CanvasLayer
## Client: the "Report a bug" form. What happened (optional), Save or Cancel; once saved it
## says where the file went and offers to open the folder. Esc closes it.

signal save_requested(description: String, screenshot: PackedByteArray)

const WIDTH := 560.0
const NOTE_HEIGHT := 120.0

var _frame: ScreenFrame
var _note: TextEdit
var _status: Label
var _save: Button
var _show: Button
var _shot := PackedByteArray()
var _saved_path := ""


func _ready() -> void:
	layer = UiLayers.MENU_SCREENS
	_frame = ScreenFrame.new("REPORT A BUG", WIDTH)
	_frame.visible = false
	add_child(_frame)
	var hint := Label.new()
	hint.theme_type_variation = &"HintLabel"
	hint.text = "Saves one file to send us: a screenshot, your settings and machine, and this session's game and performance logs. Your player name can be in the logs; folder paths and server addresses are blanked out."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = WIDTH - 40.0
	_frame.content.add_child(hint)
	_note = TextEdit.new()
	_note.name = "Note"
	_note.placeholder_text = "What happened? (optional)"
	_note.custom_minimum_size = Vector2(WIDTH - 40.0, NOTE_HEIGHT)
	_note.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_frame.content.add_child(_note)
	# The line that matters once saved: normal text, brighter than the hint above.
	_status = Label.new()
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = WIDTH - 40.0
	_frame.content.add_child(_status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	_frame.content.add_child(row)
	_save = _button(row, &"Save", "Save report", func() -> void:
		save_requested.emit(_note.text.strip_edges(), _shot))
	_show = _button(row, &"Show", "Open folder", func() -> void:
		OS.shell_show_in_file_manager(_saved_path))
	_button(row, &"Close", "Close", close)
	_frame.add_hint(&"ui_cancel", "Back")


## Opens the form for a new report, with `screenshot` (PNG bytes) to go with it.
func open(screenshot: PackedByteArray) -> void:
	_shot = screenshot
	_saved_path = ""
	_note.text = ""
	_status.text = ""
	_save.visible = true
	_show.visible = false
	_frame.visible = true
	UiStack.push(self)
	_note.grab_focus()


func close() -> void:
	_frame.visible = false
	UiStack.pop(self)


func is_open() -> bool:
	return _frame.visible


## The report is written (`path`) or could not be (empty): say so, and offer the folder.
func show_saved(path: String) -> void:
	_saved_path = path
	if path.is_empty():
		_status.text = "Could not save the report; the game log says why."
		return
	_status.text = saved_text(path)
	_save.visible = false
	_show.visible = true
	OS.shell_show_in_file_manager(path)


## The file name on a line of its own: a full path wraps mid-name and is hard to scan.
static func saved_text(path: String) -> String:
	return "Saved %s\nin %s\nSend that file to us (Discord is fine)." % [path.get_file(), path.get_base_dir()]


func _input(event: InputEvent) -> void:
	if is_open() and UiStack.is_top(self) and UiStack.is_cancel(event):
		close()
		get_viewport().set_input_as_handled()


func _button(row: HBoxContainer, id: StringName, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.name = String(id)
	b.text = text
	b.custom_minimum_size = Vector2(150, 40)
	b.pressed.connect(on_press)
	row.add_child(b)
	return b
