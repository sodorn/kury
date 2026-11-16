class_name Building
extends Area2D
## Budynek na mapie. Poczatek wezla (0,0) lezy u podstawy budynku,
## dzieki czemu sortowanie po Y i animacja "sprezynowania" dzialaja naturalnie.

const HIT_SCALE := Vector2(0.82, 0.86)
## Maksymalny ruch palca (px ekranu), przy ktorym dotyk liczy sie jako tapniecie.
const TAP_MAX_MOVE := 60.0

var building_id: String = ""

var _pressed_touch: int = -1
var _pressed_at := Vector2.ZERO
var _tween: Tween

@onready var _sprite: Sprite2D = $Sprite
@onready var _shape: CollisionShape2D = $Shape


## Wywolac po dodaniu do drzewa. `def` to wpis z data/buildings.json.
func setup(def: Dictionary) -> void:
	building_id = def.get("id", "")
	name = building_id.capitalize()
	var pos: Array = def.get("position", [0, 0])
	position = Vector2(pos[0], pos[1])

	var texture := load(def.get("sprite", "")) as Texture2D
	if texture == null:
		push_error("Building: brak grafiki dla '%s'" % building_id)
		return
	var anchor_data: Array = def.get("anchor", [texture.get_width() / 2.0, texture.get_height()])
	var anchor := Vector2(anchor_data[0], anchor_data[1])
	_sprite.texture = texture
	_sprite.offset = -anchor

	var rect := RectangleShape2D.new()
	rect.size = texture.get_size() * HIT_SCALE
	_shape.shape = rect
	_shape.position = Vector2(texture.get_width() / 2.0 - anchor.x, -anchor.y / 2.0)


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
			Events.building_tapped.emit(building_id)


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
