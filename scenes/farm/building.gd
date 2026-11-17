class_name Building
extends Area2D
## Budynek na mapie. Poczatek wezla (0,0) lezy u podstawy budynku,
## dzieki czemu sortowanie po Y dziala naturalnie.
## Grafike, pozycje i obszar dotyku ustawia sie w scenie farm.tscn,
## wiec widac je w edytorze.
## Teksty i parametry pochodza z data/buildings.json, dopasowane po `building_id`.

## Maksymalny ruch palca (px ekranu), przy ktorym dotyk liczy sie jako tapniecie.
const TAP_MAX_MOVE := 60.0

@export var building_id: String = ""

var _pressed_touch: int = -1
var _pressed_at := Vector2.ZERO
var _tween: Tween

@onready var _sprite: Sprite2D = $Sprite
@onready var _shape: CollisionShape2D = $Shape


func _ready() -> void:
	if GameData.building(building_id).is_empty():
		push_error("Building '%s': brak wpisu o id '%s' w data/buildings.json" % [name, building_id])
	if _sprite.texture == null:
		push_error("Building '%s': brak grafiki w wezle Sprite" % name)
	if _shape.shape == null:
		push_error("Building '%s': brak ksztaltu obszaru dotyku w wezle Shape" % name)


func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	# Reagujemy tylko na dotyk. Mysz na PC jest zamieniana na dotyk
	# (Project Settings > Input Devices > Pointing > Emulate Touch From Mouse).
	var touch := event as InputEventScreenTouch
	if touch == null:
		return
	if touch.pressed:
		_pressed_touch = touch.index
		_pressed_at = touch.position
		_press_feedback()
	elif touch.index == _pressed_touch:
		_pressed_touch = -1
		# Puszczenie palca daleko od miejsca nacisniecia to przeciagniecie, nie tapniecie.
		if touch.position.distance_to(_pressed_at) <= TAP_MAX_MOVE:
			_bounce()
			Events.building_tapped.emit(building_id, _sprite.texture)


func _press_feedback() -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_sprite, "scale", Vector2(1.06, 0.94), 0.07)
	_tween.tween_property(_sprite, "scale", Vector2.ONE, 0.12)


func _bounce() -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_sprite, "scale", Vector2(0.95, 1.07), 0.08)
	_tween.tween_property(_sprite, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
