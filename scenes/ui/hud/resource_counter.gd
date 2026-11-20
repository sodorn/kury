class_name ResourceCounter
extends PanelContainer
## Licznik zasobu w gornym pasku: ikona + liczba.

@export var icon: Texture2D
## Licznik pieniedzy pokazuje kwote ze zlotowkami, reszta - zwykla liczbe.
@export var is_money := false

## Kolory licznika z limitem: ostrzegawczy tuz przed koncem miejsca i czerwony,
## gdy miejsca juz nie ma.
const NEARLY_FULL_COLOR := Color(0.82, 0.52, 0.16)
const FULL_COLOR := Color(0.78, 0.20, 0.18)

var _value := -1.0
var _text := ""

@onready var _icon: TextureRect = $Row/Icon
@onready var _label: Label = $Row/Value


func _ready() -> void:
	_icon.texture = icon


func set_value(value: float) -> void:
	var text := NumberFormat.amount_only(value) if is_money else NumberFormat.grouped(int(value))
	_set_text(value, text)


## Licznik z gornym limitem, np. "37/40" przy kurach. Gdy robi sie ciasno,
## liczba zmienia kolor — inaczej gracz dowiaduje sie o pelnym kurniku
## dopiero po tym, jak pisklęta przestaja wychodzic z inkubatora.
func set_value_of(value: int, limit: int) -> void:
	_set_text(float(value), "%s/%s" % [NumberFormat.grouped(value), NumberFormat.grouped(limit)])
	if value >= limit:
		_label.add_theme_color_override("font_color", FULL_COLOR)
	elif value >= limit - 2:
		_label.add_theme_color_override("font_color", NEARLY_FULL_COLOR)
	else:
		_label.remove_theme_color_override("font_color")


func _set_text(value: float, text: String) -> void:
	if text == _text:
		return
	var animate := _value >= 0.0
	_value = value
	_text = text
	_label.text = text
	if animate:
		_pop()


func _pop() -> void:
	pivot_offset = size * 0.5
	scale = Vector2(1.12, 1.12)
	create_tween().tween_property(self, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
