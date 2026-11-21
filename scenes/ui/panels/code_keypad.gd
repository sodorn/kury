class_name CodeKeypad
extends VBoxContainer
## Klawiatura numeryczna do wpisywania kodu farmy, rysowana w samej grze.
##
## Pole tekstowe Godota nie dzialalo na telefonie: klawiatura systemowa
## w trybie numerycznym nie wpuszczala cyfr do gry (litery wchodzily, cyfry
## nie). Zamiast walczyc z warstwa wejscia przegladarki, kod wpisuje sie
## wlasnymi przyciskami — dziala tak samo na kazdym telefonie i na komputerze,
## bo nie bierze w tym udzialu zadna klawiatura systemowa.

## Kod ma dokladnie tyle cyfr. Zgodne z `Cloud.CODE_LENGTH`.
const LENGTH := 6
## Rozmiar klawisza i odstepy, w pikselach widoku.
const KEY_HEIGHT := 120
const GAP := 12

## Kod zmienil sie (po kazdej cyfrze i po kasowaniu).
signal changed(code: String)
## Gracz nacisnal klawisz zatwierdzenia przy komplecie cyfr.
signal submitted(code: String)

var _code := ""
var _display: Label
var _keys: Array[Button] = []
var _back: Button
var _accept: Button


func _ready() -> void:
	add_theme_constant_override("separation", GAP)

	_display = Label.new()
	_display.theme_type_variation = &"TitleLabel"
	_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_display)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", GAP)
	grid.add_theme_constant_override("v_separation", GAP)
	add_child(grid)
	# Uklad jak w telefonie: 1-9, potem kasowanie, 0 i zatwierdzenie.
	for digit in range(1, 10):
		grid.add_child(_make_key(str(digit)))
	# Napis, a nie znak ⌫: czcionka gry nie ma tego glifu i w przegladarce
	# wychodzil pusty kwadrat.
	_back = _make_key(tr("CODE_BACK"))
	grid.add_child(_back)
	grid.add_child(_make_key("0"))
	_accept = _make_key(tr("CODE_OK"))
	_accept.theme_type_variation = &"BuyButton"
	grid.add_child(_accept)

	_refresh()


## Jeden klawisz. Cyfry dopisuja sie do kodu, reszta ma wlasne zachowanie.
func _make_key(label: String) -> Button:
	var key := Button.new()
	key.text = label
	key.custom_minimum_size = Vector2(0, KEY_HEIGHT)
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if label.is_valid_int():
		key.pressed.connect(func() -> void: _type(label))
		_keys.append(key)
	elif label == tr("CODE_BACK"):
		key.pressed.connect(_erase)
	else:
		key.pressed.connect(func() -> void:
			if _code.length() == LENGTH:
				submitted.emit(_code))
	return key


func _type(digit: String) -> void:
	if _code.length() >= LENGTH:
		return
	_code += digit
	_refresh()
	changed.emit(_code)


func _erase() -> void:
	if _code.is_empty():
		return
	_code = _code.substr(0, _code.length() - 1)
	_refresh()
	changed.emit(_code)


func code() -> String:
	return _code


func clear() -> void:
	_code = ""
	_refresh()
	changed.emit(_code)


## Puste miejsca pokazujemy kreskami, zeby bylo widac, ilu cyfr brakuje.
func _refresh() -> void:
	var shown := ""
	for i in LENGTH:
		if i > 0:
			shown += " "
		shown += _code[i] if i < _code.length() else "–"
	_display.text = shown
	_accept.disabled = _code.length() < LENGTH
	for key in _keys:
		key.disabled = _code.length() >= LENGTH
