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
## Urwana glowa, ktora wylatuje z kury w chwili napasci.
const HEAD := preload("res://assets/sprites/animals/hen_head.svg")
## Ile glow moze fruwac naraz, zeby przy duzym lupie nie zrobil sie deszcz.
const HEADS_MAX := 3
## Dwie klatki susa. Przelaczane w locie, zeby lapy pracowaly, a lis nie
## sunal po trawie jak sanie.
const STAND := preload("res://assets/sprites/animals/fox.svg")
const LEAP := preload("res://assets/sprites/animals/fox_leap.svg")

var _leaving := false
var _pressed_touch: int = -1
var _pressed_at := Vector2.ZERO
## Sekundy do konca wizyty. Zegar nalezy do lisa, nie do nikogo innego.
var _life := 0.0
var _run := Rect2()
var _hop: Tween = null
## Gdzie odkladac plamy krwi, zeby lezaly POD zwierzetami.
var _decals: Node2D = null
## Licznik trafien nad lisem. Bez niego nikt nie wie, ze lisa odgania sie
## palcem ani ile jeszcze zostalo — koledzy zglaszali to jako pierwsza rzecz.
var _counter: Label = null

@onready var _sprite: Sprite2D = $Sprite
@onready var _feathers: CPUParticles2D = $Feathers
@onready var _blood: CPUParticles2D = $Blood
@onready var _dust: CPUParticles2D = $Dust


func _ready() -> void:
	Events.fox_visited.connect(_on_caught)
	Events.fox_scared.connect(_leave)
	Events.fox_chased.connect(_leave)
	Events.fox_killed.connect(_torn_apart)
	_build_counter()


## Duza liczba nad lisem: ile jeszcze dotkniec do przegonienia.
func _build_counter() -> void:
	_counter = Label.new()
	_counter.z_index = 4
	_counter.add_theme_font_size_override("font_size", 56)
	_counter.add_theme_color_override("font_color", Color(1, 1, 1))
	_counter.add_theme_color_override("font_outline_color", Color(0.35, 0.1, 0.06))
	_counter.add_theme_constant_override("outline_size", 14)
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_counter.size = Vector2(220, 70)
	_counter.pivot_offset = Vector2(110, 35)
	_counter.position = Vector2(-110, -210)
	_counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_counter)
	_refresh_counter()


## Przepisuje licznik ze stanu gry. Gdy lis jest juz przegoniony albo martwy,
## licznik znika — nie ma w co klikac.
func _refresh_counter() -> void:
	if _counter == null or not is_instance_valid(_counter):
		return
	var left := Game.fox_taps_left() if Game != null else 0
	_counter.visible = left > 0 and not _leaving
	_counter.text = str(left)


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
		_refresh_counter()
		return
	_refresh_counter()
	if _counter != null and is_instance_valid(_counter):
		_counter.scale = Vector2(1.5, 1.5)
		var pop := _counter.create_tween()
		pop.tween_property(_counter, "scale", Vector2.ONE, 0.18) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
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
	_pop_heads(count)
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


## Urwane glowy wylatuja z miejsca napasci, kreca sie w powietrzu i laduja
## na wybiegu, gdzie powoli znikaja razem z krwia. Groteska jest zamierzona:
## cala reszta gry jest cukierkowa i wlasnie o ten kontrast chodzi.
func _pop_heads(count: int) -> void:
	var host: Node = _decals if _decals != null else get_parent()
	if host == null:
		return
	for i in mini(maxi(1, count), HEADS_MAX):
		var head := Sprite2D.new()
		head.texture = HEAD
		head.z_index = 1
		head.position = position + Vector2(randf_range(-20.0, 20.0), randf_range(-30.0, -10.0))
		head.scale = Vector2.ONE * randf_range(0.7, 0.95)
		host.add_child(head)

		var away := head.position + Vector2(
				randf_range(-260.0, 260.0), randf_range(40.0, 120.0))
		var peak := head.position.y - randf_range(90.0, 170.0)
		var flight := randf_range(0.45, 0.7)

		var spin := head.create_tween()
		spin.tween_property(head, "rotation", randf_range(-9.0, 9.0), flight)

		var arc := head.create_tween()
		arc.tween_property(head, "position:x", away.x, flight) \
				.set_trans(Tween.TRANS_LINEAR).set_delay(0.0)
		var up := head.create_tween()
		up.tween_property(head, "position:y", peak, flight * 0.45) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		up.tween_property(head, "position:y", away.y, flight * 0.55) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		# Po ladowaniu glowa kladzie sie plasko i zostaje razem z kaluza.
		up.tween_property(head, "scale:y", head.scale.y * 0.72, 0.1)
		up.tween_interval(SPLAT_SECONDS * 0.4)
		up.tween_property(head, "modulate:a", 0.0, SPLAT_SECONDS * 0.6)
		up.tween_callback(head.queue_free)


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


## Pies dopadl lisa. Lis nie ucieka — zostaje rozszarpany na miejscu:
## kaluza krwi, strzepy futra na boki, tulow przewraca sie i powoli znika.
## Groteska jest zamierzona, tak samo jak przy urwanych glowach kur.
func _torn_apart() -> void:
	if _leaving:
		return
	_leaving = true
	set_process(false)
	input_pickable = false
	if _hop != null:
		_hop.kill()
	_refresh_counter()
	_dust.emitting = false
	_feathers.emitting = true
	_blood.emitting = true
	# Kaluza jest wyrazniejsza niz po kurze — lis jest wiekszy.
	_spill_blood(SPLATS_MAX)
	_fling_scraps()

	var host: Node = _decals if _decals != null else get_parent()
	if host != null:
		var pool := Sprite2D.new()
		pool.texture = SPLAT
		pool.z_index = 0
		pool.position = position + Vector2(0, 6)
		pool.rotation = randf_range(-0.12, 0.12)
		# Kaluza musi byc PLASKA — patrzymy na wybieg pod katem, wiec okragla
		# plama wyglada jak stojaca tarcza, a nie jak krew na trawie.
		pool.scale = Vector2(3.6, 0.8)
		pool.modulate = Color(0.78, 0.08, 0.1, 0.0)
		host.add_child(pool)
		var soak := pool.create_tween()
		soak.tween_property(pool, "modulate:a", 0.92, 0.18)
		soak.tween_interval(SPLAT_SECONDS * 0.5)
		soak.tween_property(pool, "modulate:a", 0.0, SPLAT_SECONDS * 0.5)
		soak.tween_callback(pool.queue_free)

	# Zwloki nie obracaja sie o cwierc obrotu — sprajt ma duzy offset w gore,
	# wiec obrot wokol stop wyrzucilby lisa w bok nad wybieg. Zamiast tego
	# lis osuwa sie plasko na ziemie: mocne splaszczenie, lekkie przechylenie
	# i zejscie offsetu do poziomu trawy.
	var fall := create_tween()
	fall.set_parallel(true)
	fall.tween_property(_sprite, "rotation", 0.3 if _sprite.flip_h else -0.3, 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	fall.tween_property(_sprite, "scale", Vector2(1.2, 0.34), 0.22) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fall.tween_property(_sprite, "offset:y", -16.0, 0.22) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fall.tween_property(_sprite, "modulate", Color(0.62, 0.36, 0.34), 0.4)
	# Od tego miejsca znowu po kolei. Bez tego queue_free() leci razem
	# z upadkiem i zwloki znikaja w tej samej klatce, w ktorej powstaly.
	fall.set_parallel(false)
	fall.tween_interval(1.6)
	fall.tween_property(_sprite, "modulate:a", 0.0, 1.4)
	fall.tween_callback(queue_free)


## Strzepy futra rozrzucone po trawie. Male, ciemne plamy lecace na boki.
func _fling_scraps() -> void:
	var host: Node = _decals if _decals != null else get_parent()
	if host == null:
		return
	for i in 7:
		var scrap := Sprite2D.new()
		scrap.texture = SPLAT
		scrap.z_index = 0
		scrap.position = position + Vector2(0, -12)
		scrap.rotation = randf_range(-3.0, 3.0)
		scrap.modulate = Color(0.55, 0.22, 0.12, 0.95)
		var size := randf_range(0.2, 0.42)
		scrap.scale = Vector2(size, size * 0.4)
		host.add_child(scrap)
		var away := scrap.position + Vector2(
				randf_range(-190.0, 190.0), randf_range(10.0, 90.0))
		var fly := scrap.create_tween()
		fly.set_parallel(true)
		fly.tween_property(scrap, "position", away, 0.4) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		fly.tween_property(scrap, "rotation", scrap.rotation + randf_range(-6.0, 6.0), 0.4)
		fly.set_parallel(false)
		fly.tween_interval(SPLAT_SECONDS * 0.4)
		fly.tween_property(scrap, "modulate:a", 0.0, SPLAT_SECONDS * 0.6)
		fly.tween_callback(scrap.queue_free)


## Koniec wizyty — z czasu, z przegonienia, wszystko jedno.
func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	set_process(false)
	input_pickable = false
	if _hop != null:
		_hop.kill()
	_refresh_counter()
	_dust.emitting = true
	_sprite.texture = LEAP
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
	_refresh_counter()
	var from_left := randf() < 0.5
	var y := randf_range(run.position.y + run.size.y * 0.35, run.end.y)
	position = Vector2(run.position.x - 260.0 if from_left else run.end.x + 260.0, y)
	_sprite.flip_h = not from_left

	_dust.emitting = true
	_sprite.texture = LEAP
	# Wbieganie trzymamy w tym samym polu co kice. Inaczej pies, ktory dopadnie
	# lisa tuz po wejsciu, zabija go, a zwloki dalej jada w strone wybiegu.
	_hop = create_tween()
	_hop.tween_property(self, "position", _random_spot(), 0.7) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_hop.tween_callback(func() -> void:
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

	_sprite.texture = LEAP
	_hop = create_tween()
	_hop.set_parallel()
	_hop.tween_property(self, "position", target, time).set_trans(Tween.TRANS_SINE)
	# Luk skoku robimy na samym sprajcie, zeby cien i cząstki zostaly przy ziemi.
	var arc := _hop.chain()
	arc.tween_property(_sprite, "position:y", _sprite.position.y - height, time * 0.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	arc.tween_property(_sprite, "position:y", _sprite.position.y, time * 0.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Ladowanie: lapy wracaja pod siebie, tulow sie przysiada i prostuje.
	arc.tween_callback(func() -> void: _sprite.texture = STAND)
	arc.tween_property(_sprite, "scale", Vector2(1.08, 0.9), 0.07)
	arc.tween_property(_sprite, "scale", Vector2.ONE, 0.1)
	arc.tween_interval(randf_range(0.12, 0.5))
	arc.tween_callback(_dart)


## Lis zawrocony przez plot: podbiega do zagrody, wacha i odchodzi z niczym.
## Nie da sie go dotknac — nie ma czego przeganiac, jest juz przegoniony.
func sniff_and_leave(run: Rect2) -> void:
	input_pickable = false
	if _counter != null and is_instance_valid(_counter):
		_counter.visible = false
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
