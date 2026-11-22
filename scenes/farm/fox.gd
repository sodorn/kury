class_name FarmFox
extends Area2D
## Lis na wybiegu. Wbiega, kica po placu i przez cala wizyte porywa kolejne
## kury. Gracz moze go przegonic, trafiajac w niego palcem kilkanascie razy —
## po kazdym trafieniu lis odskakuje gdzie indziej.
##
## Ile kur zginie, liczy symulacja. Scena odpowiada za pokazanie wizyty
## i za przyjecie dotkniec.
##
## WAZNE: lis sam pilnuje swojego czasu i znika, gdy ten minie — nawet
## jesli zaden sygnal z gry nie przyjdzie. Wczesniej jego zniknięcie
## zalezalo wylacznie od sygnalu `fox_visited`, a ten nie leci, gdy lis nie
## ma juz czego porwac. Skutek: lisy zostawaly na wybiegu na zawsze i
## zbieraly sie po kilka naraz.

## Ile pikseli palec moze przejechac, zeby to wciaz bylo dotkniecie, a nie przesuniecie.
const TAP_MAX_MOVE := 36.0
## Plamy krwi po ataku: ile ich maksymalnie i jak dlugo schna.
const SPLATS_MAX := 6
const SPLAT_SECONDS := 300.0
const SPLAT := preload("res://assets/ui/blood_splat.svg")

var _leaving := false
var _pressed_touch: int = -1
var _pressed_at := Vector2.ZERO
## Sekundy do konca wizyty. Zegar nalezy do lisa, nie do nikogo innego.
var _life := 0.0
var _run := Rect2()
var _hop: Tween = null
## Gdzie odkladac plamy krwi, zeby lezaly POD zwierzetami.
var _decals: Node2D = null

@onready var _sprite: Sprite2D = $Sprite
@onready var _feathers: CPUParticles2D = $Feathers
@onready var _blood: CPUParticles2D = $Blood
@onready var _dust: CPUParticles2D = $Dust


func _ready() -> void:
	Events.fox_visited.connect(_on_caught)
	Events.fox_scared.connect(_leave)


func _process(delta: float) -> void:
	if _leaving:
		return
	_life -= delta
	if _life <= 0.0:
		_leave()


func set_decals(node: Node2D) -> void:
	_decals = node


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


## Trafienie palcem. Liczenie trafien nalezy do Game — scena tylko zglasza.
## Dopoki lis nie jest przegoniony, odskakuje w inne miejsce wybiegu, zeby
## nastepne trafienie wymagalo nowego celowania.
func _hit() -> void:
	if Game.poke_fox():
		return
	var jump := create_tween()
	jump.tween_property(_sprite, "position:y", _sprite.position.y - 26.0, 0.08) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	jump.tween_property(_sprite, "position:y", _sprite.position.y, 0.1) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_dart()


## Lis dopadl kure: pióra, krew i skok. NIE konczy wizyty — lis poluje dalej,
## az skonczy mu sie czas albo gracz go przegoni.
func _on_caught(count: int) -> void:
	if _leaving:
		return
	_feathers.emitting = true
	_blood.emitting = true
	_spill_blood(count)
	var farm := get_parent().get_parent() as Node2D
	if farm != null:
		var base := farm.position
		var shake := create_tween()
		for i in 4:
			shake.tween_property(farm, "position",
					base + Vector2(randf_range(-10.0, 10.0), randf_range(-7.0, 7.0)), 0.05)
		shake.tween_property(farm, "position", base, 0.08)
	var pounce := create_tween()
	pounce.tween_property(_sprite, "position:y", _sprite.position.y - 34.0, 0.12) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pounce.tween_property(_sprite, "position:y", _sprite.position.y, 0.1) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## Plamy krwi zostaja na wybiegu i powoli znikaja. Ida do warstwy dekoracji
## POD zwierzetami: wczesniej lezaly nad nimi i wygladaly, jakby unosily sie
## w powietrzu, zaslaniajac kury. Sa tez splaszczone w pionie, bo patrzymy
## na wybieg pod katem — okragla plama wygladalaby jak stojaca tarcza.
func _spill_blood(count: int) -> void:
	var host: Node = _decals if _decals != null else get_parent()
	if host == null:
		return
	for i in mini(maxi(1, count), SPLATS_MAX):
		var splat := Sprite2D.new()
		splat.texture = SPLAT
		# Zero, nie -1: warstwa dekoracji stoi w drzewie miedzy trawa a
		# zwierzetami, wiec sama kolejnosc wezlow kladzie plamy pod kurami.
		# Z ujemnym indeksem chowaly sie pod trawa i nie bylo ich widac wcale.
		splat.z_index = 0
		splat.position = position + Vector2(randf_range(-70.0, 70.0), randf_range(-10.0, 26.0))
		splat.rotation = randf_range(-0.25, 0.25)
		var size := randf_range(0.95, 1.7)
		splat.scale = Vector2(size * 1.25, size * 0.45)
		splat.modulate = Color(1.0, 1.0, 1.0, 0.0)
		host.add_child(splat)
		var fade := splat.create_tween()
		fade.tween_property(splat, "modulate:a", 0.9, 0.12)
		fade.tween_interval(SPLAT_SECONDS * 0.4)
		fade.tween_property(splat, "modulate:a", 0.0, SPLAT_SECONDS * 0.6)
		fade.tween_callback(splat.queue_free)


## Koniec wizyty — z czasu, z przegonienia, wszystko jedno.
func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	set_process(false)
	input_pickable = false
	if _hop != null:
		_hop.kill()
	_dust.emitting = true
	var away := position.x + (520.0 if _sprite.flip_h else -520.0)
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "position:x", away, 0.6) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(_sprite, "modulate:a", 0.0, 0.6)
	tween.chain().tween_callback(queue_free)


## Wpuszcza lisa z losowej strony i puszcza go w kice po wybiegu.
## `seconds` to REALNE sekundy, ile wizyta ma trwac.
func run_through(run: Rect2, seconds: float) -> void:
	_run = run
	_life = maxf(1.0, seconds)
	var from_left := randf() < 0.5
	var y := randf_range(run.position.y + run.size.y * 0.35, run.end.y)
	position = Vector2(run.position.x - 260.0 if from_left else run.end.x + 260.0, y)
	_sprite.flip_h = not from_left

	_dust.emitting = true
	var enter := create_tween()
	enter.tween_property(self, "position", _random_spot(), 0.7) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	enter.tween_callback(func() -> void:
		_dust.emitting = false
		_dart())


## Losowy punkt na wybiegu, dokad lis moze skoczyc.
func _random_spot() -> Vector2:
	return Vector2(
			randf_range(_run.position.x + 60.0, _run.end.x - 60.0),
			randf_range(_run.position.y + _run.size.y * 0.3, _run.end.y - 20.0))


## Jeden kic: lis przeskakuje w nowe miejsce po luku i od razu szykuje
## nastepny. Zamiast bujac sie w kolko w jednym punkcie, przemierza wybieg —
## i trzeba za nim nadazyc palcem.
func _dart() -> void:
	if _leaving:
		return
	if _hop != null:
		_hop.kill()
	var target := _random_spot()
	_sprite.flip_h = target.x > position.x
	var distance := position.distance_to(target)
	var time := clampf(distance / 900.0, 0.22, 0.6)
	var height := clampf(distance * 0.12, 16.0, 46.0)

	_hop = create_tween()
	_hop.set_parallel()
	_hop.tween_property(self, "position", target, time).set_trans(Tween.TRANS_SINE)
	# Luk skoku robimy na samym sprajcie, zeby cien i cząstki zostaly przy ziemi.
	var arc := _hop.chain()
	arc.tween_property(_sprite, "position:y", _sprite.position.y - height, time * 0.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	arc.tween_property(_sprite, "position:y", _sprite.position.y, time * 0.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	arc.tween_interval(randf_range(0.12, 0.5))
	arc.tween_callback(_dart)


## Lis zawrocony przez plot: podbiega do zagrody, wacha i odchodzi z niczym.
## Nie da sie go dotknac — nie ma czego przeganiac, jest juz przegoniony.
func sniff_and_leave(run: Rect2) -> void:
	input_pickable = false
	set_process(false)
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
	tween.tween_property(_sprite, "rotation", 0.12, 0.3).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_sprite, "rotation", -0.12, 0.3).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_sprite, "rotation", 0.0, 0.2)
	tween.tween_callback(func() -> void: _sprite.flip_h = from_left)
	tween.tween_property(self, "position:x", edge, 0.9) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void: _dust.emitting = false)
	tween.tween_callback(queue_free)
