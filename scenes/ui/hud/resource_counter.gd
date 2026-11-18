class_name ResourceCounter
extends PanelContainer
## Licznik zasobu w gornym pasku: ikona + liczba.

@export var icon: Texture2D
## Licznik pieniedzy pokazuje kwote ze zlotowkami, reszta - zwykla liczbe.
@export var is_money := false

var _value := -1.0
var _text := ""

@onready var _icon: TextureRect = $Row/Icon
@onready var _label: Label = $Row/Value


func _ready() -> void:
	_icon.texture = icon


func set_value(value: float) -> void:
	var text := NumberFormat.amount_only(value) if is_money else NumberFormat.grouped(int(value))
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
