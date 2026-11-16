class_name ResourceCounter
extends PanelContainer
## Licznik zasobu w gornym pasku: ikona + liczba.

@export var icon: Texture2D

var _value: int = -1

@onready var _icon: TextureRect = $Row/Icon
@onready var _label: Label = $Row/Value


func _ready() -> void:
	_icon.texture = icon


func set_value(value: int) -> void:
	if value == _value:
		return
	var animate := _value >= 0
	_value = value
	_label.text = NumberFormat.grouped(value)
	if animate:
		_pop()


func _pop() -> void:
	pivot_offset = size * 0.5
	scale = Vector2(1.12, 1.12)
	create_tween().tween_property(self, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
