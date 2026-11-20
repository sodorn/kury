class_name FarmFox
extends Area2D
## Lis na wybiegu. Biega przez kilka sekund i dopiero potem zabiera kury —
## w tym czasie gracz moze go przegonic, trafiajac w niego palcem kilka razy.
##
## Sam lup liczy symulacja; scena odpowiada wylacznie za pokazanie wizyty
## i za przyjecie dotkniec.

## Ile pikseli palec moze przejechac, zeby to wciaz bylo dotkniecie, a nie przesuniecie.
const TAP_MAX_MOVE := 36.0
## Plamy krwi po ataku: ile ich maksymalnie i jak dlugo schna.
const SPLATS_MAX := 4
const SPLAT_SECONDS := 300.0
const SPLAT := preload("res://assets/ui/blood_splat.svg")

var _taps_left := 3
var _leaving := false
var _pressed_touch: int = -1
var _pressed_at := Vector2.ZERO

@onready var _sprite: Sprite2D = $Sprite
@onready var _feathers: CPUParticles2D = $Feathers
@onready var _blood: CPUParticles2D = $Blood
@onready var _dust: CPUParticles2D = $Dust


func _ready() -> void:
	_taps_left = int(GameData.balance().get("fox", {}).get("scare_taps", 3))
	Events.fox_visited.connect(_on_caught)
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


## Lis dopadl kury. Krew, chmura piór, szarpniecie wybiegu i ucieczka z lupem.
func _on_caught(count: int) -> void:
	if _leaving:
		return
	_feathers.emitting = true
	_blood.emitting = true
	_spill_blood(count)
	# Szarpniecie calym wybiegiem — najtansza rzecz, ktora sprawia,
	# ze zdarzenie czuc, a nie tylko widac.
	var farm := get_parent().get_parent() as Node2D
	if farm != null:
		var base := farm.position
		var shake := create_tween()
		for i in 5:
			shake.tween_property(farm, "position",
					base + Vector2(randf_range(-14.0, 14.0), randf_range(-10.0, 10.0)), 0.05)
		shake.tween_property(farm, "position", base, 0.08)
	# Skok na kure, potem ucieczka.
	var pounce := create_tween()
	pounce.tween_property(_sprite, "position:y", _sprite.position.y - 34.0, 0.12) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pounce.tween_property(_sprite, "position:y", _sprite.position.y, 0.1) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	pounce.tween_callback(_on_gone)


## Plamy krwi zostaja na wybiegu i powoli znikaja. Siedza w rodzicu lisa,
## a nie w nim samym, zeby nie odjechaly razem z uciekajacym lisem.
func _spill_blood(count: int) -> void:
	var host := get_parent()
	if host == null:
		return
	for i in mini(maxi(1, count), SPLATS_MAX):
		var splat := Sprite2D.new()
		splat.texture = SPLAT
		splat.z_index = 1
		splat.position = position + Vector2(randf_range(-70.0, 70.0), randf_range(-16.0, 34.0))
		splat.rotation = randf_range(-PI, PI)
		splat.scale = Vector2.ONE * randf_range(0.95, 1.8)
		splat.modulate = Color(1.0, 1.0, 1.0, 0.0)
		host.add_child(splat)
		var fade := splat.create_tween()
		fade.tween_property(splat, "modulate:a", 0.9, 0.12)
		fade.tween_interval(SPLAT_SECONDS * 0.4)
		fade.tween_property(splat, "modulate:a", 0.0, SPLAT_SECONDS * 0.6)
		fade.tween_callback(splat.queue_free)


## Lis znika — przegoniony albo z lupem. Jedno i drugie konczy wizyte.
func _on_gone() -> void:
	if _leaving:
		return
	_leaving = true
	input_pickable = false
	_dust.emitting = true
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

	# Kurz spod lap, dopoki lis wbiega na wybieg.
	_dust.emitting = true
	var tween := create_tween()
	tween.tween_property(self, "position:x", run.get_center().x, minf(1.2, seconds * 0.25)) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func() -> void: _dust.emitting = false)
	# Reszta wizyty: lis krazy w miejscu i czeka, az gracz zareaguje.
	var prowl := create_tween().set_loops()
	prowl.tween_property(_sprite, "rotation", 0.09, 0.45).set_trans(Tween.TRANS_SINE)
	prowl.tween_property(_sprite, "rotation", -0.09, 0.45).set_trans(Tween.TRANS_SINE)


## Lis zawrocony przez plot: podbiega do zagrody, wacha i odchodzi z niczym.
## Nie da sie go dotknac — nie ma czego przeganiac, jest juz przegoniony.
func sniff_and_leave(run: Rect2) -> void:
	input_pickable = false
	var from_left := randf() < 0.5
	var y := randf_range(run.position.y + run.size.y * 0.35, run.end.y)
	var edge := run.position.x - 260.0 if from_left else run.end.x + 260.0
	var near := run.position.x + run.size.x * 0.22 if from_left else run.end.x - run.size.x * 0.22
	position = Vector2(edge, y)
	_sprite.flip_h = not from_left

	_dust.emitting = true
	var tween := create_tween()
	tween.tween_property(self, "position:x", near, 1.0) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# Chwila wahania przy plocie, zeby bylo widac, ze zawrocil, a nie przeszedl.
	tween.tween_property(_sprite, "rotation", 0.12, 0.3).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_sprite, "rotation", -0.12, 0.3).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_sprite, "rotation", 0.0, 0.2)
	tween.tween_callback(func() -> void: _sprite.flip_h = from_left)
	tween.tween_property(self, "position:x", edge, 0.9) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void: _dust.emitting = false)
	tween.tween_callback(queue_free)
