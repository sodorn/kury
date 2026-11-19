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
## Rasa kury, ktora zniosla to jajko. Decyduje o cenie i o odcieniu skorupki.
var breed_id: String = ""

@onready var _sprite: Sprite2D = $Sprite


## Ustawia rase i miejsce. Wolane zaraz po dodaniu do sceny.
func setup(egg_breed_id: String, spot: Vector2) -> void:
	breed_id = egg_breed_id
	position = spot
	var tint := String(GameData.breed(breed_id).get("egg_tint", ""))
	if not tint.is_empty() and _sprite != null:
		_sprite.modulate = Color(tint)


func _ready() -> void:
	var tint := String(GameData.breed(breed_id).get("egg_tint", ""))
	if not tint.is_empty():
		_sprite.modulate = Color(tint)
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
			# Jajka potrafia na siebie zachodzic, a Godot rozsyla dotkniecie do
			# kazdego obszaru pod palcem. Bez tego jedno dotkniecie zbieraloby
			# dwa jajka naraz.
			get_viewport().set_input_as_handled()


## Zbiera jajko: zglasza to do Game i odgrywa animacje znikniecia.
func collect() -> void:
	if collected:
		return
	if not Game.collect_egg_of_breed(breed_id):
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
