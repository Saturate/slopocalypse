class_name UiText
extends RefCounted
## Labels for screens built in code, on the shared type scale: a screen asks for roughly the
## size it wants and gets the nearest style, so no screen invents its own sizes again.
## 22 and up is a heading (stencil font), 18 to 21 body text, smaller is the hint size.


static func label(text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	if size >= 22:
		l.theme_type_variation = &"HeadingLabel"
	elif size >= 18:
		l.add_theme_font_size_override(&"font_size", UiPalette.BODY)
	else:
		l.add_theme_font_size_override(&"font_size", UiPalette.HINT)
	if colour != UiPalette.ACCENT or size < 22:
		l.add_theme_color_override(&"font_color", colour)
	return l
