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

@onready var _sprite: Sprite2D = $Sprite
@onready var _dust: CPUParticles2D = $Dust


func _ready() -> void:
	_home = position


func _process(delta: float) -> void:
	if not _chasing:
		return
	if _target == null or not is_instance_valid(_target):
		_go_home()
		return
	# Pies trzyma sie tuz za lisem, po tej stronie, z ktorej do niego biegl.
	var side := -CHASE_GAP if _target.position.x > position.x else CHASE_GAP
	var want := Vector2(_target.position.x + side, _target.position.y + 6.0)
	position = position.lerp(want, clampf(delta * 3.2, 0.0, 1.0))
	_sprite.flip_h = _target.position.x > position.x


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
	_sprite.flip_h = _home.x > position.x
	var back := create_tween()
	back.tween_property(self, "position", _home, 0.9) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	back.tween_callback(func() -> void: _sprite.flip_h = false)
