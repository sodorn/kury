class_name FarmChicken
extends Node2D
## Kura (albo pisklę) chodzaca po wybiegu. Sama grafika i ruch — stan stada
## trzyma Game. Punkt (0,0) wezla lezy pod nogami, dzieki czemu sortowanie
## po Y ustawia zwierze poprawnie wzgledem plotu i reszty stada.

const CHICK_SPRITE := "res://assets/sprites/animals/chick.svg"
const SPEED := 44.0
## Pisklęta sa drobniejsze i bardziej rozbiegane.
const CHICK_SPEED := 58.0
const CHICK_SCALE := Vector2(0.72, 0.82)
## Ile sekund zwierze stoi i dziobie miedzy spacerami.
const REST_SECONDS := Vector2(1.2, 3.4)
const CHICK_REST_SECONDS := Vector2(0.4, 1.4)
const BOB_SPEED := 9.0
const BOB_HEIGHT := 3.5
const ARRIVED_DISTANCE := 8.0

var breed_id: String = ""
var is_chick := false
## Zwierze jest w trakcie animacji znikania — scena ma go juz nie liczyc.
var leaving := false

var _bounds := Rect2()
var _target := Vector2.ZERO
var _rest_left := 0.0
var _rest_time := 0.0
var _bob := 0.0
var _facing := 1.0
var _speed := SPEED
var _rest_range := REST_SECONDS

@onready var _sprite: Sprite2D = $Sprite


## `bounds` to obszar w ukladzie farmy, po ktorym zwierze moze chodzic.
func setup(animal_breed_id: String, bounds: Rect2, chick: bool = false) -> void:
	breed_id = animal_breed_id
	is_chick = chick
	_bounds = bounds
	_speed = CHICK_SPEED if chick else SPEED
	_rest_range = CHICK_REST_SECONDS if chick else REST_SECONDS

	var path: String = CHICK_SPRITE if chick else String(GameData.breed(breed_id).get("sprite", ""))
	var texture := load(path) as Texture2D
	if texture == null:
		push_error("FarmChicken: brak grafiki dla rasy '%s'" % breed_id)
	else:
		_sprite.texture = texture

	position = _random_point()
	_target = _random_point()
	_rest_left = randf_range(0.0, _rest_range.y)
	_rest_time = maxf(_rest_left, 0.01)
	# Lekko rozne rozmiary, zeby stado nie wygladalo jak kopie jednej kury.
	var size := randf_range(CHICK_SCALE.x, CHICK_SCALE.y) if chick else randf_range(0.82, 0.95)
	scale = Vector2(size, size)


func _process(delta: float) -> void:
	if _rest_left > 0.0:
		_rest_left -= delta
		_peck()
		return
	_walk(delta)


func _walk(delta: float) -> void:
	var to_target := _target - position
	if to_target.length() <= ARRIVED_DISTANCE:
		_rest_time = randf_range(_rest_range.x, _rest_range.y)
		_rest_left = _rest_time
		_target = _random_point()
		return
	var step := to_target.normalized() * _speed * delta
	position += step
	if absf(step.x) > 0.01:
		_facing = signf(step.x)
		_sprite.flip_h = _facing < 0.0
	_bob += delta * BOB_SPEED
	_sprite.position.y = -absf(sin(_bob)) * BOB_HEIGHT
	_sprite.rotation = 0.0


## Podczas postoju zwierze co chwile pochyla sie do ziemi.
func _peck() -> void:
	_sprite.position.y = 0.0
	var phase := (_rest_time - _rest_left) * 4.2
	var dip := maxf(0.0, sin(phase))
	_sprite.rotation = 0.22 * dip * _facing


## Zwierze znika z wybiegu (sprzedane albo wyroslo) — podskakuje i gasnie.
func leave() -> void:
	if leaving:
		return
	leaving = true
	set_process(false)
	var tween := create_tween().set_parallel()
	tween.tween_property(_sprite, "position:y", _sprite.position.y - 120.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_sprite, "scale", Vector2(0.4, 0.4), 0.4)
	tween.tween_property(_sprite, "modulate:a", 0.0, 0.4)
	tween.chain().tween_callback(queue_free)


func _random_point() -> Vector2:
	return Vector2(
		randf_range(_bounds.position.x, _bounds.end.x),
		randf_range(_bounds.position.y, _bounds.end.y))
