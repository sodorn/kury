class_name UiTheme
extends RefCounted
## Jedno miejsce na wyglad UI: kolory, fonty i style paneli.

const INK := Color("4b2e16")
const INK_SOFT := Color("8a6a4a")
const CREAM := Color("fff3d6")
const PAPER := Color("fffaf0")

const FONT_BODY: Font = preload("res://assets/fonts/Baloo2-600.ttf")
const FONT_TITLE: Font = preload("res://assets/fonts/Baloo2-800.ttf")


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font = FONT_BODY
	theme.default_font_size = 40

	theme.set_color("font_color", "Label", INK)
	theme.set_constant("line_spacing", "Label", -6)

	theme.set_type_variation("TitleLabel", "Label")
	theme.set_font("font", "TitleLabel", FONT_TITLE)
	theme.set_font_size("font_size", "TitleLabel", 68)

	theme.set_type_variation("CounterLabel", "Label")
	theme.set_font("font", "CounterLabel", FONT_TITLE)
	theme.set_font_size("font_size", "CounterLabel", 44)

	theme.set_type_variation("NoteLabel", "Label")
	theme.set_font_size("font_size", "NoteLabel", 32)
	theme.set_color("font_color", "NoteLabel", INK_SOFT)

	theme.set_stylebox("panel", "PanelContainer", _pill())
	theme.set_type_variation("SheetPanel", "PanelContainer")
	theme.set_stylebox("panel", "SheetPanel", _sheet())
	return theme


static func _pill() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = CREAM
	box.border_color = INK
	box.set_border_width_all(5)
	box.set_corner_radius_all(40)
	box.content_margin_left = 12
	box.content_margin_right = 22
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	box.shadow_color = Color(0, 0, 0, 0.22)
	box.shadow_size = 2
	box.shadow_offset = Vector2(0, 6)
	return box


static func _sheet() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = PAPER
	box.border_color = INK
	box.set_border_width_all(6)
	box.border_width_bottom = 0
	box.corner_radius_top_left = 56
	box.corner_radius_top_right = 56
	box.set_content_margin_all(48)
	box.content_margin_top = 36
	box.shadow_color = Color(0, 0, 0, 0.25)
	box.shadow_size = 12
	return box
