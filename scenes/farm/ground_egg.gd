class_name GroundEgg
extends Area2D
## Jajko lezace na wybiegu. Dotkniecie zbiera je do magazynu.
## Punkt (0,0) wezla lezy u podstawy jajka (sortowanie po Y).

## Maksymalny ruch palca (px ekranu), przy ktorym dotyk liczy sie jako tapniecie.
const TAP_MAX_MOVE := 60.0

var _pressed_touch: int = -1
var _pressed_at := Vector2.ZERO
## Jajko juz zebrane — scena ma go nie liczyc.
var collected := false

@onready var _sprite: Sprite2D = $Sprite


func _ready() -> void:
	# Pojawienie sie: jajko "wyskakuje" z ziemi.
	_sprite.scale = Vector2(0.2, 0.2)
	var tween := create_tween()
	tween.tween_property(_sprite, "scale", Vector2(1.08, 0.92), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_sprite, "scale", Vector2.ONE, 0.12)


func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	var touch := event as InputEventScreenTouch
	if touch == null or collected:
		return
	if touch.pressed:
		_pressed_touch = touch.index
		_pressed_at = touch.position
	elif touch.index == _pressed_touch:
		_pressed_touch = -1
		if touch.position.distance_to(_pressed_at) <= TAP_MAX_MOVE:
			collect()


## Zbiera jajko: zglasza to do Game i odgrywa animacje znikniecia.
func collect() -> void:
	if collected:
		return
	if not Game.collect_egg():
		queue_free()
		return
	collected = true
	set_deferred("monitorable", false)
	input_pickable = false
	var tween := create_tween().set_parallel()
	tween.tween_property(_sprite, "position:y", _sprite.position.y - 90.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_sprite, "scale", Vector2(0.4, 0.4), 0.35)
	tween.tween_property(_sprite, "modulate:a", 0.0, 0.35)
	tween.chain().tween_callback(queue_free)
