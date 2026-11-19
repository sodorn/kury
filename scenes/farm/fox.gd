extends Area2D
## Lis na wybiegu. Biega przez kilka sekund i dopiero potem zabiera kury —
## w tym czasie gracz moze go przegonic, trafiajac w niego palcem kilka razy.
##
## Sam lup liczy symulacja; scena odpowiada wylacznie za pokazanie wizyty
## i za przyjecie dotkniec.

## Ile pikseli palec moze przejechac, zeby to wciaz bylo dotkniecie, a nie przesuniecie.
const TAP_MAX_MOVE := 36.0

var _taps_left := 3
var _leaving := false
var _pressed_touch: int = -1
var _pressed_at := Vector2.ZERO

@onready var _sprite: Sprite2D = $Sprite


func _ready() -> void:
	_taps_left = int(GameData.balance().get("fox", {}).get("scare_taps", 3))
	Events.fox_visited.connect(_on_gone)
	Events.fox_scared.connect(_on_gone)


func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	var touch := event as InputEventScreenTouch
	if touch == null or _leaving:
		return
	if touch.pressed:
		_pressed_touch = touch.index
		_pressed_at = touch.position
		return
	if touch.index != _pressed_touch:
		return
	_pressed_touch = -1
	if touch.position.distance_to(_pressed_at) > TAP_MAX_MOVE:
		return
	get_viewport().set_input_as_handled()
	_hit()


## Trafienie: lis podskakuje, a po ostatnim ucieka z pustymi lapami.
func _hit() -> void:
	_taps_left -= 1
	if _taps_left > 0:
		var jump := create_tween()
		jump.tween_property(_sprite, "position:y", _sprite.position.y - 26.0, 0.1) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		jump.tween_property(_sprite, "position:y", _sprite.position.y, 0.14) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		return
	# Decyzje podejmuje Game; scena tylko zglasza trafienia.
	Game.scare_fox()


## Lis znika — przegoniony albo z lupem. Jedno i drugie konczy wizyte.
func _on_gone() -> void:
	if _leaving:
		return
	_leaving = true
	input_pickable = false
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "position:x", position.x + (520.0 if _sprite.flip_h else -520.0), 0.6) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(_sprite, "modulate:a", 0.0, 0.6)
	tween.chain().tween_callback(queue_free)


## Wpuszcza lisa z losowej strony i prowadzi go na srodek wybiegu, gdzie
## zostaje do konca wizyty — stoi w jednym miejscu, zeby dalo sie w niego trafic.
func run_through(run: Rect2, seconds: float) -> void:
	var from_left := randf() < 0.5
	var y := randf_range(run.position.y + run.size.y * 0.35, run.end.y)
	position = Vector2(run.position.x - 260.0 if from_left else run.end.x + 260.0, y)
	_sprite.flip_h = not from_left

	var tween := create_tween()
	tween.tween_property(self, "position:x", run.get_center().x, minf(1.2, seconds * 0.25)) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# Reszta wizyty: lis krazy w miejscu i czeka, az gracz zareaguje.
	var prowl := create_tween().set_loops()
	prowl.tween_property(_sprite, "rotation", 0.09, 0.45).set_trans(Tween.TRANS_SINE)
	prowl.tween_property(_sprite, "rotation", -0.09, 0.45).set_trans(Tween.TRANS_SINE)
