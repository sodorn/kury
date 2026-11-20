class_name FarmChicken
extends Node2D
## Kura (albo pisklę) chodzaca po wybiegu. Sama grafika i ruch — stan stada
## trzyma Game. Punkt (0,0) wezla lezy pod nogami, dzieki czemu sortowanie
## po Y ustawia zwierze poprawnie wzgledem plotu i reszty stada.

const CHICK_SPRITE := "res://assets/sprites/animals/chick.svg"
const SPEED := 44.0
## Pisklęta sa drobniejsze i bardziej rozbiegane.
const CHICK_SPEED := 58.0
## Rozmiary podniesione o 40% wzgledem wersji 5.0 — w kure duzo latwiej trafic
## palcem na telefonie.
const CHICK_SCALE := Vector2(1.01, 1.15)
const HEN_SCALE := Vector2(1.15, 1.33)
## Chora kura ledwo sie wlecze, jest zzielniala i parauje od niej mgla.
const SICK_SPEED := 11.0
const SICK_TINT := Color(0.62, 0.78, 0.52)
const SICK_REST_SECONDS := Vector2(4.0, 8.0)
## O tyle chora kura przechyla sie i opada — wyglada na oklapnieta.
const SICK_DROOP := 0.17
const SICK_SINK := 10.0
## Ile sekund zwierze stoi i dziobie miedzy spacerami.
const REST_SECONDS := Vector2(1.2, 3.4)
const CHICK_REST_SECONDS := Vector2(0.4, 1.4)
const BOB_SPEED := 9.0
const BOB_HEIGHT := 3.5
const ARRIVED_DISTANCE := 8.0

var breed_id: String = ""
var is_chick := false
## Kura chora: nie znosi jaj, ma nad soba banke z krzyzem i wkrotce padnie.
var is_sick := false
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
@onready var _mist: CPUParticles2D = $Mist


## `bounds` to obszar w ukladzie farmy, po ktorym zwierze moze chodzic.
func setup(animal_breed_id: String, bounds: Rect2, chick: bool = false, sick: bool = false) -> void:
	breed_id = animal_breed_id
	is_chick = chick
	_bounds = bounds

	var path: String = CHICK_SPRITE if chick else String(GameData.breed(breed_id).get("sprite", ""))
	var texture := load(path) as Texture2D
	if texture == null:
		push_error("FarmChicken: brak grafiki dla rasy '%s'" % breed_id)
	else:
		_sprite.texture = texture

	position = _random_point()
	_target = _random_point()
	# Lekko rozne rozmiary, zeby stado nie wygladalo jak kopie jednej kury.
	var range_used := CHICK_SCALE if chick else HEN_SCALE
	var size := randf_range(range_used.x, range_used.y)
	scale = Vector2(size, size)
	set_sick(sick)
	_rest_left = randf_range(0.0, _rest_range.y)
	_rest_time = maxf(_rest_left, 0.01)


## Przestawia zwierze miedzy stanem zdrowym i chorym.
func set_sick(sick: bool) -> void:
	is_sick = sick
	_speed = SICK_SPEED if sick else (CHICK_SPEED if is_chick else SPEED)
	_rest_range = SICK_REST_SECONDS if sick else (CHICK_REST_SECONDS if is_chick else REST_SECONDS)
	if _sprite != null:
		_sprite.modulate = SICK_TINT if sick else Color.WHITE
		# Oklapniecie: kura przechyla sie na bok i osiada nizej.
		_sprite.rotation = SICK_DROOP if sick else 0.0
		_sprite.position.y = SICK_SINK if sick else 0.0
	if _mist != null:
		_mist.emitting = sick


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
