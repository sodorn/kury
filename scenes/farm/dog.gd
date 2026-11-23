class_name FarmDog
extends Node2D
## Pies podworzowy. Stoi przy kurniku, dopoki jest spokojnie. Gdy na wybieg
## wejdzie lis, rusza za nim i goni go tak dlugo, ile trwa wizyta — lis przez
## ten czas dalej porywa kury, ale ucieka wczesniej, niz gdyby psa nie bylo.
##
## O tym, CZY i JAK SZYBKO pies da rade, decyduje symulacja: ona skraca
## wizyte lisa. Scena pokazuje pogon i wraca na miejsce.

## Jak blisko lisa pies sie trzyma, zeby bylo widac pogon, a nie nakladanie.
const CHASE_GAP := 150.0

var _home := Vector2.ZERO
var _target: Node2D = null
var _chasing := false

## Kundel i owczarek to dwa rozne psy, nie ten sam w dwoch rozmiarach.
const MUTT := preload("res://assets/sprites/animals/dog.svg")
const MUTT_LEAP := preload("res://assets/sprites/animals/dog_leap.svg")
const SHEPHERD := preload("res://assets/sprites/animals/dog_shepherd.svg")
const SHEPHERD_LEAP := preload("res://assets/sprites/animals/dog_shepherd_leap.svg")

## Dwie klatki biegu wybranego psa: stojaca i z wyrzuconymi lapami.
var _stand: Texture2D = MUTT
var _leap: Texture2D = MUTT_LEAP

## Ile sekund trwa jeden sus. Pies biegnie, a nie sunie jak sanie.
const HOP_SECONDS := 0.32
const HOP_HEIGHT := 18.0

var _hop_phase := 0.0
var _rest_y := 0.0

@onready var _sprite: Sprite2D = $Sprite
@onready var _dust: CPUParticles2D = $Dust


func _ready() -> void:
	_home = position
	_rest_y = _sprite.position.y
	show_breed(Game.state.dog_level if Game.state != null else 1)


## Dobiera wyglad i rozmiar do kupionego psa.
func show_breed(level: int) -> void:
	if level >= 2:
		_stand = SHEPHERD
		_leap = SHEPHERD_LEAP
		# Owczarek jest wiekszy od kundla juz samym sprajtem (248 vs 210 px),
		# wiec skale podbijamy tylko odrobine. Przy 1.5 pies zaslanial pol
		# kurnika i wygladal jak kon.
		_sprite.offset = Vector2(0, -64)
		scale = Vector2(1.34, 1.34)
	else:
		_stand = MUTT
		_leap = MUTT_LEAP
		_sprite.offset = Vector2(0, -56)
		scale = Vector2(1.3, 1.3)
	_sprite.texture = _stand


func _process(delta: float) -> void:
	if not _chasing:
		return
	if _target == null or not is_instance_valid(_target):
		_go_home()
		return
	# Pies trzyma sie tuz za lisem, po tej stronie, z ktorej do niego biegl.
	var side := -CHASE_GAP if _target.position.x > position.x else CHASE_GAP
	var want := Vector2(_target.position.x + side, _target.position.y + 6.0)
	var before := position
	position = position.lerp(want, clampf(delta * 3.2, 0.0, 1.0))
	_sprite.flip_h = _target.position.x > position.x

	# Susy zamiast sunięcia. Faza idzie od PRZEBYTEJ drogi, wiec pies
	# podskakuje tylko wtedy, gdy naprawde biegnie, a stojac stoi spokojnie.
	var moved := position.distance_to(before)
	if moved < 0.4:
		_sprite.position.y = lerpf(_sprite.position.y, _rest_y, clampf(delta * 8.0, 0.0, 1.0))
		_sprite.texture = _stand
		return
	_hop_phase += delta / HOP_SECONDS
	var lift: float = absf(sin(_hop_phase * PI))
	_sprite.position.y = _rest_y - lift * HOP_HEIGHT
	# Lapy wyrzucone, gdy pies jest w powietrzu; pod sobą, gdy dotyka ziemi.
	_sprite.texture = _leap if lift > 0.35 else _stand
	# Lekkie sciskanie przy ziemi i rozciaganie w locie — stary trik
	# animacji, dzieki ktoremu ruch przestaje wygladac jak przesuwanie
	# obrazka.
	_sprite.scale = Vector2(1.0 + 0.06 * (1.0 - lift), 1.0 + 0.08 * lift)


## Rusza za lisem. Wolane przez farme, gdy lis wejdzie na wybieg.
func chase(fox: Node2D, _run: Rect2) -> void:
	_target = fox
	_chasing = true
	_dust.emitting = true
	set_process(true)
	# Szczeknięcie: krotki podskok, zeby bylo widac, ze pies zareagowal.
	var bark := create_tween()
	bark.tween_property(_sprite, "position:y", _sprite.position.y - 22.0, 0.1) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	bark.tween_property(_sprite, "position:y", _sprite.position.y, 0.12) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## Lis poszedl — pies wraca pod kurnik i siada.
func _go_home() -> void:
	_chasing = false
	_target = null
	_dust.emitting = false
	set_process(false)
	_sprite.position.y = _rest_y
	_sprite.scale = Vector2.ONE
	_sprite.texture = _stand
	_sprite.flip_h = _home.x > position.x
	var back := create_tween()
	back.tween_property(self, "position", _home, 0.9) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	back.tween_callback(func() -> void: _sprite.flip_h = false)
