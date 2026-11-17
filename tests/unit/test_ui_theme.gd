extends GdUnitTestSuite
## The project theme: every Control gets it (even under a CanvasLayer), the window scales the
## UI, and the type variations carry the palette's fonts, sizes and colours.


func test_project_theme_is_the_ui_theme() -> void:
	assert_str(str(ProjectSettings.get_setting("gui/theme/custom"))).is_equal("res://core/ui/ui_theme.tres")
	assert_object(ThemeDB.get_project_theme()).is_instanceof(UiTheme)


func test_window_scales_the_ui() -> void:
	assert_str(str(ProjectSettings.get_setting("display/window/stretch/mode"))).is_equal("canvas_items")
	assert_str(str(ProjectSettings.get_setting("display/window/stretch/aspect"))).is_equal("expand")


func test_label_under_a_canvas_layer_gets_the_body_font() -> void:
	var layer: CanvasLayer = auto_free(CanvasLayer.new())
	add_child(layer)
	var label := Label.new()
	layer.add_child(label)
	assert_str(label.get_theme_font(&"font").resource_path).is_equal(UiTheme.BODY_FONT)
	assert_int(label.get_theme_font_size(&"font_size")).is_equal(UiPalette.BODY)
	assert_that(label.get_theme_color(&"font_color")).is_equal(UiPalette.TEXT)


func test_title_variation_uses_heading_font_and_accent() -> void:
	var label: Label = auto_free(Label.new())
	label.theme_type_variation = &"TitleLabel"
	add_child(label)
	assert_str(label.get_theme_font(&"font").resource_path).is_equal(UiTheme.HEADING_FONT)
	assert_int(label.get_theme_font_size(&"font_size")).is_equal(UiPalette.TITLE)
	assert_that(label.get_theme_color(&"font_color")).is_equal(UiPalette.ACCENT)


func test_hud_labels_are_outlined() -> void:
	for variation: StringName in [&"HudLabel", &"HudNumber"]:
		var label: Label = auto_free(Label.new())
		label.theme_type_variation = variation
		add_child(label)
		assert_int(label.get_theme_constant(&"outline_size")).is_greater(0)


func test_panels_and_buttons_are_steel_plates() -> void:
	var panel: PanelContainer = auto_free(PanelContainer.new())
	add_child(panel)
	var plate := panel.get_theme_stylebox(&"panel") as SteelPlate
	assert_object(plate).is_not_null()
	assert_bool(plate.rivets).is_true()
	var button: Button = auto_free(Button.new())
	add_child(button)
	assert_object(button.get_theme_stylebox(&"normal")).is_instanceof(SteelPlate)
	var ring := button.get_theme_stylebox(&"focus") as SteelPlate
	assert_bool(ring.filled).is_false()
	assert_that(ring.outline).is_equal(UiPalette.ACCENT)


func test_accent_button_is_amber_with_dark_text() -> void:
	var button: Button = auto_free(Button.new())
	button.theme_type_variation = &"AccentButton"
	add_child(button)
	var plate := button.get_theme_stylebox(&"normal") as SteelPlate
	assert_that(plate.fill).is_equal(UiPalette.ACCENT)
	assert_bool(plate.stripe).is_true()
	assert_that(button.get_theme_color(&"font_color")).is_equal(UiPalette.INK)


func test_plate_draws_without_errors_at_any_size() -> void:
	var ci := RenderingServer.canvas_item_create()
	var plate := SteelPlate.new()
	plate.rivets = true
	plate.stripe = true
	for size: Vector2 in [Vector2(1, 1), Vector2(40, 20), Vector2(600, 400)]:
		plate.draw(ci, Rect2(Vector2.ZERO, size))
	RenderingServer.free_rid(ci)
	assert_object(SteelPlate.grain()).is_not_null()
