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
## 13.0.4: w nocy pies wbiega za lisem do kurnika i walczy niewidocznie.
var _raiding := false
var _raid_tween: Tween = null

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
	Events.dog_fled.connect(_go_home)
	show_breed(Game.state.dog_level if Game.state != null else 1)


## Dobiera wyglad i rozmiar do kupionego psa. 13.0.2: piec psow. Kundle
## (1-3) i terier (5) na razie z tego samego sprajtu kundla - inny rozmiar
## i masc; wlasne grafiki w ZADANIA (etap E).
func show_breed(level: int) -> void:
	_sprite.modulate = Color.WHITE
	if level == 4:
		_stand = SHEPHERD
		_leap = SHEPHERD_LEAP
		# Owczarek jest wiekszy od kundla juz samym sprajtem (248 vs 210 px),
		# wiec skale podbijamy tylko odrobine. Przy 1.5 pies zaslanial pol
		# kurnika i wygladal jak kon.
		_sprite.offset = Vector2(0, -64)
		scale = Vector2(1.07, 1.07)
	else:
		_stand = MUTT
		_leap = MUTT_LEAP
		_sprite.offset = Vector2(0, -56)
		match level:
			1:  # stary gluchy - siwy
				scale = Vector2(1.0, 1.0)
				_sprite.modulate = Color(0.82, 0.8, 0.78)
			2:  # maly tchorzliwy
				scale = Vector2(0.78, 0.78)
			3:  # duzy agresywny - wiekszy i ciemniejszy
				scale = Vector2(1.28, 1.28)
				_sprite.modulate = Color(0.72, 0.62, 0.55)
			_:  # terier - maly, czarny podpalany
				scale = Vector2(0.85, 0.85)
				_sprite.modulate = Color(0.45, 0.36, 0.3)
	_sprite.texture = _stand


func _process(delta: float) -> void:
	if _raiding:
		var fox := _target as FarmFox
		if fox == null or not is_instance_valid(fox) \
				or fox.phase == FarmFox.Phase.LEAVE or fox.phase == FarmFox.Phase.DEAD:
			_raiding = false
			_sprite.modulate.a = 1.0
			_go_home()
		return
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
	# 13.0.2 (wlasciciel): pies biegl dupa do przodu. Sprajt patrzy w PRAWO,
	# wiec odwracamy go tylko przy biegu w lewo - wedlug kierunku ruchu,
	# a stojac pies patrzy na lisa.
	var dx := position.x - before.x
	if absf(dx) > 0.3:
		_sprite.flip_h = dx < 0.0
	elif absf(_target.position.x - position.x) > 4.0:
		_sprite.flip_h = _target.position.x < position.x

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


## Noc: pies chwile nasluchuje (aż zauwazy lisa), potem biegnie do drzwi
## kurnika i znika w srodku. Walka liczy sie w symulacji jak zwykle.
func raid(fox: Node2D, door: Vector2) -> void:
	_target = fox
	_raiding = true
	_chasing = false
	set_process(true)
	var notice := clampf(float(Game.state.dog_interval()) * 0.5, 0.4, 4.0) if Game.state != null else 1.0
	var go := create_tween()
	_raid_tween = go
	go.tween_interval(notice)
	go.tween_callback(func() -> void:
		_dust.emitting = true
		_sprite.flip_h = door.x < position.x)
	go.tween_property(self, "position", door + Vector2(18, 16), 0.7) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	go.tween_property(_sprite, "modulate:a", 0.0, 0.2)
	go.tween_callback(func() -> void: _dust.emitting = false)


## Lis poszedl — pies wraca pod kurnik i siada.
func _go_home() -> void:
	if _raid_tween != null and _raid_tween.is_valid():
		_raid_tween.kill()
	_raiding = false
	_sprite.modulate.a = 1.0
	_chasing = false
	_target = null
	_dust.emitting = false
	set_process(false)
	_sprite.position.y = _rest_y
	_sprite.scale = Vector2.ONE
	_sprite.texture = _stand
	# Do budy biegnie przodem: w lewo = odwrocony.
	_sprite.flip_h = _home.x < position.x
	var back := create_tween()
	back.tween_property(self, "position", _home, 0.9) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	back.tween_callback(func() -> void: _sprite.flip_h = false)
