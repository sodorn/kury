class_name FarmChicken
extends Node2D
## Kura chodzaca po wybiegu. Sama grafika i ruch — stan stada trzyma Game.
## Punkt (0,0) wezla lezy pod nogami kury, dzieki czemu sortowanie po Y
## ustawia ja poprawnie wzgledem plotu i innych kur.

const SPEED := 44.0
## Ile sekund kura stoi i dziobie miedzy spacerami.
const REST_SECONDS := Vector2(1.2, 3.4)
const BOB_SPEED := 9.0
const BOB_HEIGHT := 3.5
const ARRIVED_DISTANCE := 8.0

var breed_id: String = ""

var _bounds := Rect2()
var _target := Vector2.ZERO
var _rest_left := 0.0
var _rest_time := 0.0
var _bob := 0.0
var _facing := 1.0

@onready var _sprite: Sprite2D = $Sprite


## `bounds` to obszar w ukladzie farmy, po ktorym kura moze chodzic.
func setup(hen_breed_id: String, bounds: Rect2) -> void:
	breed_id = hen_breed_id
	_bounds = bounds
	var def := GameData.breed(breed_id)
	var texture := load(def.get("sprite", "")) as Texture2D
	if texture == null:
		push_error("FarmChicken: brak grafiki dla rasy '%s'" % breed_id)
	else:
		_sprite.texture = texture
	position = _random_point()
	_target = _random_point()
	_rest_left = randf_range(0.0, REST_SECONDS.y)
	_rest_time = _rest_left
	# Lekko rozne rozmiary, zeby stado nie wygladalo jak kopie jednej kury.
	var size := randf_range(0.82, 0.95)
	scale = Vector2(size, size)


func _process(delta: float) -> void:
	if _rest_left > 0.0:
		_rest_left -= delta
		_peck(delta)
		return
	_walk(delta)


func _walk(delta: float) -> void:
	var to_target := _target - position
	if to_target.length() <= ARRIVED_DISTANCE:
		_rest_time = randf_range(REST_SECONDS.x, REST_SECONDS.y)
		_rest_left = _rest_time
		_target = _random_point()
		return
	var step := to_target.normalized() * SPEED * delta
	position += step
	if absf(step.x) > 0.01:
		_facing = signf(step.x)
		_sprite.flip_h = _facing < 0.0
	_bob += delta * BOB_SPEED
	_sprite.position.y = -absf(sin(_bob)) * BOB_HEIGHT
	_sprite.rotation = 0.0


## Podczas postoju kura co chwile pochyla sie do ziemi.
func _peck(_delta: float) -> void:
	_sprite.position.y = 0.0
	var phase := (_rest_time - _rest_left) * 4.2
	var dip := maxf(0.0, sin(phase))
	_sprite.rotation = 0.22 * dip * _facing


func _random_point() -> Vector2:
	return Vector2(
		randf_range(_bounds.position.x, _bounds.end.x),
		randf_range(_bounds.position.y, _bounds.end.y))
