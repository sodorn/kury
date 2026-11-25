class_name SlideButton
extends Button
## Przycisk "przesun, zeby potwierdzic". Wlasciciel (25.11): okienko "na
## pewno?" przy kazdej transakcji bylo meczace, a bez niego latwo o
## przypadkowe dotkniecie. Teraz pole trzeba przeciagnac palcem od lewej do
## prawej - kolor wypelnia je w miare przesuwania, a akcja rusza, gdy
## galka minie 2/3 drogi (od 12.20; wczesniej do samego konca). Puszczony
## wczesniej wraca na start.
##
## Dziedziczy po Button, zeby napis, zawijanie, wyszarzenie i motyw dzialaly
## jak dotad. Zwykle klikniecie jest przechwytywane w _gui_input (wolanym
## PRZED obsluga z Button), wiec sygnal `pressed` leci wylacznie po
## przesunieciu do konca - kod, ktory sie do niego podlacza, nie musi nic
## wiedziec o suwaku.

## Ile trzeba przesunac (0..1), zeby akcja ruszyla. Wlasciciel (25.11):
## "ciezko przesunac cale do konca, za duzo smyrania" — wystarczaja 2/3.
const DONE_AT := 0.66
## Najdluzsza droga galki w pikselach. Szerokie suwaki (rozbudowy, pasza)
## nie wymagaja juz przeciagniecia przez caly ekran: galka jedzie najwyzej
## tyle, a 2/3 z tego to okolo 240 px - jeden ruch kciuka.
const MAX_TRAVEL := 360.0

## Niski suwak na jedna linijke (12.21, karta rasy w sklepie, pasza,
## szczepienie): mniejsze marginesy pionowe i odstep na galke.
@export var compact := false:
	set(value):
		compact = value
		if is_inside_tree():
			_restyle()
## Ruch palca, po ktorym wiadomo, ze to przesuwanie, a nie przewijanie.
const INTENT_PX := 14.0
## Srednica galki wzgledem wysokosci pola.
const KNOB_SHARE := 0.78

## Leci przy dotknieciu bez przesuniecia - panel moze podpowiedziec "przesun".
signal tapped_only

var _progress := 0.0
var _dragging := false
var _sliding := false
var _start := Vector2.ZERO
var _back_tween: Tween = null
var _back: Control = null
var _knob: Control = null
## Style tla wziete z motywu PRZED podmiana na puste (do rysowania toru).
var _boxes := {}


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	_build()
	resized.connect(_redraw)
	theme_changed.connect(_restyle)
	# Button przerysowuje sie sam, gdy zmienia sie napis albo wyszarzenie;
	# tlo i galka sa osobnymi dziecmi, wiec pociagamy je za nim.
	draw.connect(_on_self_draw)
	_restyle()


func _build() -> void:
	# Tlo i wypelnienie rysuje dziecko ZA przyciskiem (show_behind_parent),
	# a napis rysuje sam Button nad nim. Galka jest na wierzchu.
	_back = Control.new()
	_back.name = "Track"
	_back.show_behind_parent = true
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_back.draw.connect(_draw_track)
	add_child(_back)
	_knob = Control.new()
	_knob.name = "Knob"
	_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_knob.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_knob.draw.connect(_draw_knob)
	add_child(_knob)


## Wlasne tlo zamiast tla Button: Button rysuje teraz tylko napis, a o lewy
## margines wiecej, zeby galka nie wchodzila na tekst.
var _restyling := false


func _restyle() -> void:
	# Nadpisanie stylu samo wywoluje theme_changed - bez blokady petla.
	if _restyling:
		return
	_restyling = true
	var variation := theme_type_variation if theme_type_variation != &"" else &"Button"
	# Najpierw zdejmujemy wlasne nadpisania - inaczej motyw zwrocilby nasze
	# puste style zamiast prawdziwego wygladu przycisku.
	var states := ["normal", "hover", "pressed", "disabled", "hover_pressed", "focus"]
	for state_name in states:
		remove_theme_stylebox_override(state_name)
	_boxes = {
		"normal": get_theme_stylebox("normal", variation),
		"disabled": get_theme_stylebox("disabled", variation),
	}
	var base: StyleBox = _boxes["normal"]
	for state_name in states:
		var empty := StyleBoxEmpty.new()
		if base != null:
			empty.content_margin_left = base.get_content_margin(SIDE_LEFT)
			empty.content_margin_right = base.get_content_margin(SIDE_RIGHT)
			empty.content_margin_top = base.get_content_margin(SIDE_TOP)
			empty.content_margin_bottom = base.get_content_margin(SIDE_BOTTOM)
		if compact:
			empty.content_margin_top = 6.0
			empty.content_margin_bottom = 6.0
			empty.content_margin_left = 10.0 + 58.0
			empty.content_margin_right = 12.0
		else:
			empty.content_margin_left += 74.0
		add_theme_stylebox_override(state_name, empty)
	_redraw()
	_restyling = false


var _was_disabled := false


func _on_self_draw() -> void:
	if disabled != _was_disabled:
		_was_disabled = disabled
		_kill_back()
		_progress = 0.0
		_dragging = false
		_sliding = false
	_redraw()


func _redraw() -> void:
	if _back != null:
		_back.queue_redraw()
	if _knob != null:
		_knob.queue_redraw()


func progress() -> float:
	return _progress


## Galka ma stala wielkosc kciuka - przy przyciskach na kilka linijek
## rosla do polowy pola i zaslaniala napis.
func _knob_size() -> float:
	if compact:
		return clampf(size.y - 20.0, 36.0, 52.0)
	return clampf((size.y - 18.0) * KNOB_SHARE, 40.0, 76.0)


func _travel() -> float:
	return clampf(size.x - _knob_size() - 24.0, 1.0, MAX_TRAVEL)


## Droga galki w pikselach (dla testow, ktore przesuwaja suwak myszka).
func travel() -> float:
	return _travel()


## Galka minela prog - puszczenie teraz wykona akcje.
func ready_to_fire() -> bool:
	return _sliding and _progress >= DONE_AT


func _draw_track() -> void:
	var box: StyleBox = _boxes.get("disabled" if disabled else "normal")
	var rect := Rect2(Vector2.ZERO, size)
	if box != null:
		_back.draw_style_box(box, rect)
	if disabled or _progress <= 0.0:
		return
	# Wypelnienie: ten sam ksztalt, ciemniejszy kolor, od lewej do galki.
	var flat := box as StyleBoxFlat
	var fill := StyleBoxFlat.new()
	if flat != null:
		fill.bg_color = flat.bg_color.darkened(0.25)
		# Za progiem pole jasnieje - widac, ze mozna puscic.
		if _progress >= DONE_AT:
			fill.bg_color = flat.bg_color.lightened(0.18)
		fill.set_corner_radius_all(flat.corner_radius_top_left)
		fill.border_color = flat.border_color
		fill.set_border_width_all(flat.border_width_left)
	else:
		fill.bg_color = Color(0.4, 0.7, 0.3)
		fill.set_corner_radius_all(30)
	var width := _knob_size() + 24.0 + _travel() * _progress
	_back.draw_style_box(fill, Rect2(Vector2.ZERO, Vector2(minf(width, size.x), size.y)))


func _draw_knob() -> void:
	var d := _knob_size()
	var center := Vector2(12.0 + d * 0.5 + _travel() * _progress, size.y * 0.5)
	var ink := Color("5C4030")
	var alpha := 0.35 if disabled else 1.0
	_knob.draw_circle(center + Vector2(0, 4), d * 0.5, Color(0, 0, 0, 0.16 * alpha))
	_knob.draw_circle(center, d * 0.5, Color(1.0, 0.99, 0.96, alpha))
	_knob.draw_arc(center, d * 0.5, 0.0, TAU, 48, Color(ink, 0.75 * alpha), 4.0, true)
	# Za progiem zamiast strzalek "ptaszek": puszczaj, akcja ruszy.
	if _progress >= DONE_AT and not disabled:
		var t := d * 0.2
		var tick := PackedVector2Array([center + Vector2(-t, 0.0),
				center + Vector2(-t * 0.25, t * 0.75), center + Vector2(t * 1.1, -t * 0.8)])
		_knob.draw_polyline(tick, Color("3E8E41"), 6.0, true)
		return
	# Strzalki ">>" na galce mowia, w ktora strone ciagnac.
	var s := d * 0.17
	for k in 2:
		var x := center.x - s * 0.9 + k * s * 1.1
		var points := PackedVector2Array([Vector2(x - s * 0.5, center.y - s),
				Vector2(x + s * 0.5, center.y), Vector2(x - s * 0.5, center.y + s)])
		_knob.draw_polyline(points, Color(ink, alpha), 5.0, true)


# --- dotyk / mysz -----------------------------------------------------------


func _gui_input(event: InputEvent) -> void:
	# Wszystkie klikniecia i ruchy obslugujemy sami. accept_event() przed
	# wbudowana obsluga Button sprawia, ze samo dotkniecie nic nie robi.
	# Dotyk (ScreenTouch/ScreenDrag) tylko polykamy: Button reaguje na
	# puszczenie palca jak na klikniecie, a suwak liczy z myszy, w ktora gra
	# i tak zamienia kazdy dotyk (emulate_mouse_from_touch).
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		accept_event()
		return
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if disabled:
			accept_event()
			return
		if button.pressed:
			_dragging = true
			_sliding = false
			_start = button.position
			_kill_back()
		else:
			_release()
		accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _dragging:
		var moved := motion.position - _start
		if not _sliding:
			# Ruch w pionie to przewijanie listy, nie przesuwanie suwaka.
			if absf(moved.y) > INTENT_PX and absf(moved.y) > absf(moved.x):
				_dragging = false
				return
			if moved.x > INTENT_PX:
				_sliding = true
		if _sliding:
			_set_progress(clampf((moved.x - INTENT_PX * 0.5) / _travel(), 0.0, 1.0))
			accept_event()


func _release() -> void:
	var was_sliding := _sliding
	_dragging = false
	_sliding = false
	if _progress >= DONE_AT:
		_set_progress(1.0)
		pressed.emit()
		_snap_back(0.35)
		return
	if not was_sliding:
		tapped_only.emit()
		_nudge()
		return
	_snap_back(0.0)


func _set_progress(value: float) -> void:
	_progress = value
	_redraw()


func _kill_back() -> void:
	if _back_tween != null and _back_tween.is_valid():
		_back_tween.kill()


func _snap_back(delay: float) -> void:
	_kill_back()
	_back_tween = create_tween()
	if delay > 0.0:
		_back_tween.tween_interval(delay)
	_back_tween.tween_method(_set_progress, _progress, 0.0, 0.25) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Dotkniecie bez przesuniecia: galka podskakuje w prawo i wraca - widac,
## ze trzeba ciagnac.
func _nudge() -> void:
	_kill_back()
	_back_tween = create_tween()
	_back_tween.tween_method(_set_progress, 0.0, 0.14, 0.12).set_trans(Tween.TRANS_QUAD)
	_back_tween.tween_method(_set_progress, 0.14, 0.0, 0.2).set_trans(Tween.TRANS_BOUNCE) \
			.set_ease(Tween.EASE_OUT)

