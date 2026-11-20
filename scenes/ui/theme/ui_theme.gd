class_name UiTheme
extends RefCounted
## Jedno miejsce na wyglad UI: kolory, fonty i style paneli oraz przyciskow.

const INK := Color("5C4030")
const INK_SOFT := Color("8A6A55")
const CREAM := Color("FFF6E2")
const PAPER := Color("FFFCF5")
const GOLD := Color("FFD98A")
const GOLD_DARK := Color("E8A94A")
const GREEN := Color("A8DE8C")

## Polowa szerokosci suwaka przewijania w pikselach widoku (1080 px szerokosci).
## Caly pasek wychodzi dwa razy szerszy, czyli okolo 2,5 mm na telefonie.
const SCROLLBAR_WIDTH := 26

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
	# 36, a nie 44: na gorny pasek musza wejsc cztery liczniki, a najdluzsze
	# z nich to kwota w rodzaju "1 500 000" i stan kurnika "260+34/260".
	theme.set_font_size("font_size", "CounterLabel", 34)

	theme.set_type_variation("NoteLabel", "Label")
	theme.set_font_size("font_size", "NoteLabel", 32)
	theme.set_color("font_color", "NoteLabel", INK_SOFT)

	theme.set_stylebox("panel", "PanelContainer", _pill())
	theme.set_type_variation("SheetPanel", "PanelContainer")
	theme.set_stylebox("panel", "SheetPanel", _sheet())

	_apply_button(theme, "Button", CREAM)
	theme.set_type_variation("PrimaryButton", "Button")
	_apply_button(theme, "PrimaryButton", GOLD)

	_apply_line_edit(theme)

	_apply_scrollbar(theme)

	theme.set_stylebox("background", "ProgressBar", _bar(Color("EFE3CC")))
	theme.set_stylebox("fill", "ProgressBar", _bar(GOLD_DARK))
	theme.set_color("font_color", "ProgressBar", INK)
	theme.set_font_size("font_size", "ProgressBar", 28)
	return theme


## Pasek przewijania w panelach. Domyslny jest cienki jak wlos i na telefonie
## nie da sie go zlapac palcem — przewijanie szlo wylacznie przeciaganiem
## zawartosci, przez co latwo bylo przypadkiem nacisnac przycisk pod palcem.
## Suwak ma wiec szerokosc kciuka i widoczny tor, zeby bylo w co celowac.
static func _apply_scrollbar(theme: Theme) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color("EFE3CC")
	track.set_corner_radius_all(SCROLLBAR_WIDTH / 2)
	track.content_margin_left = SCROLLBAR_WIDTH
	track.content_margin_right = SCROLLBAR_WIDTH

	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color("C9A57C")
	grabber.set_corner_radius_all(SCROLLBAR_WIDTH / 2)
	grabber.set_border_width_all(2)
	grabber.border_color = Color(INK_SOFT, 0.45)

	var grabber_pressed := grabber.duplicate() as StyleBoxFlat
	grabber_pressed.bg_color = GOLD_DARK

	for bar in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", bar, track)
		theme.set_stylebox("grabber", bar, grabber)
		theme.set_stylebox("grabber_highlight", bar, grabber_pressed)
		theme.set_stylebox("grabber_pressed", bar, grabber_pressed)


## Pole tekstowe (wpisywanie kodu farmy). Bez tego Godot rysuje swoje
## domyslne, ciemne pole, ktore na kremowym arkuszu wyglada jak obcy element.
static func _apply_line_edit(theme: Theme) -> void:
	theme.set_font("font", "LineEdit", FONT_TITLE)
	theme.set_font_size("font_size", "LineEdit", 44)
	theme.set_color("font_color", "LineEdit", INK)
	theme.set_color("font_placeholder_color", "LineEdit", Color(INK_SOFT, 0.55))
	theme.set_color("caret_color", "LineEdit", INK)
	theme.set_color("selection_color", "LineEdit", Color(GOLD, 0.5))
	var box := StyleBoxFlat.new()
	box.bg_color = Color("FFFCF5")
	box.set_corner_radius_all(16)
	box.set_border_width_all(4)
	box.border_color = Color("E0CBA8")
	box.set_content_margin_all(18)
	theme.set_stylebox("normal", "LineEdit", box)
	var focused := box.duplicate() as StyleBoxFlat
	focused.border_color = GOLD_DARK
	theme.set_stylebox("focus", "LineEdit", focused)
	var disabled := box.duplicate() as StyleBoxFlat
	disabled.bg_color = Color("F0E8DA")
	theme.set_stylebox("read_only", "LineEdit", disabled)


static func _apply_button(theme: Theme, type_name: String, base: Color) -> void:
	theme.set_font("font", type_name, FONT_TITLE)
	theme.set_font_size("font_size", type_name, 40)
	theme.set_color("font_color", type_name, INK)
	theme.set_color("font_pressed_color", type_name, INK)
	theme.set_color("font_hover_color", type_name, INK)
	theme.set_color("font_disabled_color", type_name, Color(INK, 0.38))
	theme.set_stylebox("normal", type_name, _button(base, 8))
	theme.set_stylebox("hover", type_name, _button(base.lightened(0.08), 8))
	theme.set_stylebox("pressed", type_name, _button(base.darkened(0.08), 2))
	theme.set_stylebox("disabled", type_name, _button(Color(base, 0.45), 0, Color(INK_SOFT, 0.45)))
	theme.set_stylebox("focus", type_name, StyleBoxEmpty.new())


static func _button(bg: Color, shadow: int, border: Color = INK_SOFT) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(5)
	box.set_corner_radius_all(32)
	box.content_margin_left = 34
	box.content_margin_right = 34
	box.content_margin_top = 16
	box.content_margin_bottom = 18
	if shadow > 0:
		box.shadow_color = Color(0, 0, 0, 0.18)
		box.shadow_size = shadow
		box.shadow_offset = Vector2(0, 5)
	return box


static func _bar(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(18)
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	return box


static func _pill() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = CREAM
	box.border_color = INK_SOFT
	box.set_border_width_all(5)
	box.set_corner_radius_all(40)
	box.content_margin_left = 12
	box.content_margin_right = 22
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	box.shadow_color = Color(0, 0, 0, 0.18)
	box.shadow_size = 2
	box.shadow_offset = Vector2(0, 6)
	return box


static func _sheet() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = PAPER
	box.border_color = INK_SOFT
	box.set_border_width_all(6)
	box.border_width_bottom = 0
	box.corner_radius_top_left = 56
	box.corner_radius_top_right = 56
	box.set_content_margin_all(48)
	box.content_margin_top = 36
	box.shadow_color = Color(0, 0, 0, 0.22)
	box.shadow_size = 12
	return box
