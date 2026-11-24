class_name FarmFox
extends Area2D
## Lis. Od 12.18 caly jego wystep wyglada tak:
##
##   1. CZAI SIE w krzakach na polnoc albo na poludnie od wybiegu (10-30 s):
##      zza krzaka wystaja uszy, co chwile wychyla pysk.
##   2. PODCHODZI truchtem pod plot.
##   3. Pod plotem weszy. Symulacja losuje plot:
##        - plot wygral: lis drapie, zawraca i znika w krzakach,
##        - plot przegral: lis przeskakuje plot i wpada na wybieg.
##   4. POLUJE: biega lukami, przystaje, rzuca sie na kury. Gracz odgania go
##      palcem (licznik nad glowa), pies go goni.
##   5. ODCHODZI: przeskakuje plot z powrotem i chowa sie w krzakach.
##
## Ile kur zginie i kiedy, liczy symulacja. Scena tylko pokazuje.
##
## Animacja: lis jest zlozony z czesci (tools/gen_fox.py) - dwie polowy
## tulowia zginaja sie w stawie, cztery lapy pracuja galopem (przednie
## w tyl, tylne w przod i na odwrot), glowa kiwa, ogon faluje. Zawraca
## lukiem i obraca sie przez "spłaszczenie", a nie w jednej klatce.
## Wlasciciel (24.11): "jak czworonog, a nie jak samolot".
##
## WAZNE: lis sam pilnuje, czy wizyta w grze trwa (Game.state.fox_visit_left).
## Do 12.17 polegal tylko na sygnalach - a gdy lis sam skonczyl polowanie,
## zaden sygnal nie lecial i lis bez licznika biegal dalej (farma 272180).

enum Phase { LURK, APPROACH, AT_FENCE, TURN_BACK, ENTER, HUNT, LEAVE, DEAD }

## Ile pikseli palec moze przejechac, zeby to wciaz bylo dotkniecie.
const TAP_MAX_MOVE := 36.0
## Plamy krwi po ataku: ile ich maksymalnie i jak dlugo schna.
const SPLATS_MAX := 6
const SPLAT_SECONDS := 300.0
const SPLAT := preload("res://assets/ui/blood_splat.svg")
## Urwana glowa, ktora wylatuje z kury w chwili napasci.
const HEAD := preload("res://assets/sprites/animals/hen_head.svg")
const HEADS_MAX := 3
## Szerokosc sylwetki lisa w jednostkach sceny przy skali 1 (stary fox.svg).
const BODY_WIDTH := 196.0

## Ruch. Predkosci w pikselach swiata na sekunde.
const RUN_SPEED := 390.0
const TROT_SPEED := 120.0
const ACCEL := 950.0
## Jak szybko lis skreca (radiany na sekunde). Dzieki temu zawraca lukiem.
const TURN_RATE := 5.0
## Dlugosc jednego kroku galopu i truchtu - faza lap idzie od przebytej drogi.
const GALLOP_STRIDE := 135.0
const TROT_STRIDE := 80.0
## Jak szybko lis "obraca sie" przez splaszczenie (skala x na sekunde).
const FACE_TURN_SPEED := 8.0

## Amplitudy ruchu czesci (radiany i piksele).
const GALLOP_LEG := 0.78
const TROT_LEG := 0.42
const GALLOP_FLEX := 0.11
const GALLOP_LIFT := 16.0

var phase: Phase = Phase.HUNT

var _pressed_touch: int = -1
var _pressed_at := Vector2.ZERO
## Sekundy do konca wizyty - bezpiecznik na wypadek, gdyby gra milczala.
var _life := 0.0
var _hunt_time := 0.0
var _run := Rect2()
## Gdzie odkladac plamy krwi, zeby lezaly POD zwierzetami.
var _decals: Node2D = null
## Licznik trafien nad lisem.
var _counter: Label = null

## Plan wystepu ustawiony przez farme.
var _bush_spot := Vector2.ZERO
var _fence_point := Vector2.ZERO
var _inside_point := Vector2.ZERO
var _exits: Array[Dictionary] = []
var _lurk_left := 0.0
var _approach_speed := TROT_SPEED
var _verdict := ""
var _wait_left := 0.0
var _peek_left := 1.5
var _peek: Tween = null

## Ruch: kierunek, predkosc, cel.
var _heading := 0.0
var _speed := 0.0
var _target := Vector2.ZERO
var _pause_left := 0.0
var _facing := 1.0
var _gait_phase := 0.0
var _gait := "stand"
## Skok: z punktu do punktu po luku. Po wyladowaniu wolamy _leap_done.
var _leaping := false
var _leap_from := Vector2.ZERO
var _leap_to := Vector2.ZERO
var _leap_t := 0.0
var _leap_dur := 0.5
var _leap_h := 50.0
var _leap_done: Callable = Callable()
var _lift := 0.0
var _crouch := 0.0
var _dig := 0.0
var _clock := 0.0
## Napasc, ktora przyszla, gdy lis jeszcze przeskakiwal plot. Symulacja
## zabiera pierwsza kure w chwili wejscia, a scena pokazuje ja po wyladowaniu.
var _pending_kills := 0
var _pending_breeds: Array = []

## Szkielet.
var _rig: Node2D = null
var _body: Node2D = null
var _rear: Sprite2D = null
var _front: Sprite2D = null
var _head: Sprite2D = null
var _tail: Sprite2D = null
var _shadow: Sprite2D = null
var _legs := {}

@onready var _feathers: CPUParticles2D = $Feathers
@onready var _blood: CPUParticles2D = $Blood
@onready var _dust: CPUParticles2D = $Dust


func _ready() -> void:
	_build_rig()
	Events.fox_visited.connect(_on_caught)
	Events.fox_victims.connect(_on_victims)
	Events.fox_scared.connect(leave)
	Events.fox_chased.connect(leave)
	Events.fox_left.connect(leave)
	Events.fox_killed.connect(_torn_apart)
	_build_counter()
	_apply_pose(0.0, true)


# --- szkielet ---------------------------------------------------------


## Sklada lisa z czesci. Wspolrzedne z FoxRigData sa w ukladzie starego
## fox.svg; punkt ORIGIN odpowiada (0, 0) wezla lisa.
func _build_rig() -> void:
	_rig = Node2D.new()
	_rig.name = "Rig"
	add_child(_rig)
	move_child(_rig, 0)
	_shadow = _part("shadow", _rig, FoxRigData.ORIGIN)
	_body = Node2D.new()
	_body.name = "Body"
	_body.position = FoxRigData.JOINT - FoxRigData.ORIGIN
	_rig.add_child(_body)
	_rear = _part("rear", _body, FoxRigData.JOINT)
	_front = _part("front", _body, FoxRigData.JOINT)
	# Ogon i tylne lapy wisza na tylnej polowie, przednie i glowa - na
	# przedniej. Lapy i ogon rysuja sie ZA tulowiem, jak w starym rysunku.
	_tail = _part("tail", _rear, FoxRigData.JOINT)
	_tail.show_behind_parent = true
	for name: String in ["hind_far", "hind_near"]:
		_legs[name] = _leg(name, _rear)
	for name: String in ["front_far", "front_near"]:
		_legs[name] = _leg(name, _front)
	_head = _part("head", _front, FoxRigData.JOINT)


## Jedna czesc lisa jako sprajt. `parent_pivot` to punkt (w ukladzie
## fox.svg), w ktorym lezy (0, 0) rodzica.
func _part(name: String, parent: Node2D, parent_pivot: Vector2) -> Sprite2D:
	var data: Array = FoxRigData.PARTS[name]
	var sprite := Sprite2D.new()
	sprite.name = name.capitalize().replace(" ", "")
	sprite.texture = load(String(data[0]))
	var center: Vector2 = data[1]
	var pivot: Vector2 = data[2]
	sprite.position = pivot - parent_pivot
	sprite.offset = center - pivot
	parent.add_child(sprite)
	return sprite


func _leg(name: String, parent: Sprite2D) -> Sprite2D:
	var data: Array = FoxRigData.PARTS["leg"]
	var leg := Sprite2D.new()
	leg.name = "Leg_" + name
	leg.texture = load(String(data[0]))
	leg.offset = (data[1] as Vector2) - (data[2] as Vector2)
	leg.position = (FoxRigData.HIPS[name] as Vector2) - FoxRigData.JOINT
	leg.show_behind_parent = true
	# Lapy z dalszej strony sa ciemniejsze - inaczej czworonog wyglada
	# jak dwunog z doklejonym cieniem.
	if name.ends_with("far"):
		leg.modulate = Color(0.78, 0.7, 0.66)
	parent.add_child(leg)
	return leg


## Licznik trafien nad lisem.
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


## Licznik widac tylko wtedy, gdy lis jest na wybiegu i da sie go odgonic.
func _refresh_counter() -> void:
	if _counter == null or not is_instance_valid(_counter):
		return
	var left := Game.fox_taps_left() if Game != null and Game.state != null else 0
	_counter.visible = left > 0 and phase == Phase.HUNT
	_counter.text = str(left)


func set_decals(node: Node2D) -> void:
	_decals = node


## Szerokosc lisa w swiecie (do porownan z psem w tescie dymnym).
func world_width() -> float:
	return BODY_WIDTH * absf(scale.x)


# --- plan wystepu (wola farma) -----------------------------------------


## Lis wychodzi z krzaka i za `seconds` sekund ma stac pod plotem.
## `bush_spot` - miejsce za krzakiem, `fence_point` - gdzie stanie pod
## plotem, `inside` - gdzie wyladuje po przeskoczeniu, `exits` - punkty
## pod plotem i krzaki do ucieczki.
func lurk(run: Rect2, bush_spot: Vector2, fence_point: Vector2, inside: Vector2,
		exits: Array[Dictionary], seconds: float, approach_seconds: float) -> void:
	_run = run
	_bush_spot = bush_spot
	_fence_point = fence_point
	_inside_point = inside
	_exits = exits
	position = bush_spot
	phase = Phase.LURK
	input_pickable = false
	var walk := maxf(0.5, approach_seconds)
	_lurk_left = maxf(0.3, seconds - walk)
	# Odrobine szybciej niz wynika z czasu: rozpedzanie i skret przed plotem
	# zjadaja chwile, a symulacja liczy rowno `approach_seconds`.
	_approach_speed = clampf(bush_spot.distance_to(fence_point) / (walk * 0.8), 50.0, RUN_SPEED)
	_set_facing(1.0 if fence_point.x >= bush_spot.x else -1.0, true)
	_crouch = 1.0
	# Wychodzi z cienia krzaka, a nie pojawia sie znikad.
	_rig.modulate.a = 0.0
	create_tween().tween_property(_rig, "modulate:a", 1.0, 0.8)
	_refresh_counter()


## Lis bez fazy w krzakach - stoi juz pod plotem (np. po wczytaniu gry).
func stand_at_fence(run: Rect2, fence_point: Vector2, inside: Vector2,
		exits: Array[Dictionary]) -> void:
	_run = run
	_fence_point = fence_point
	_inside_point = inside
	_exits = exits
	_bush_spot = _nearest_exit(fence_point).get("bush", fence_point)
	position = fence_point
	_set_facing(1.0 if inside.x >= fence_point.x else -1.0, true)
	phase = Phase.AT_FENCE
	input_pickable = false
	_wait_left = 0.0


## Symulacja: lis wchodzi na wybieg. `seconds` - ile najdluzej zostanie.
func enter_run(seconds: float) -> void:
	_life = maxf(1.0, seconds)
	match phase:
		Phase.AT_FENCE:
			_jump_in()
		Phase.LURK, Phase.APPROACH:
			# Wizyta juz trwa, a lis jeszcze idzie: biegnie pod plot galopem.
			if _peek != null and _peek.is_valid():
				_peek.kill()
			_verdict = "enter"
			phase = Phase.APPROACH
			_approach_speed = RUN_SPEED
		_:
			pass


## Symulacja: plot zawrocil lisa.
func repel() -> void:
	match phase:
		Phase.AT_FENCE:
			_turn_back()
		Phase.LURK, Phase.APPROACH:
			_verdict = "repel"
		_:
			pass


## Stara sciezka 12.17: lis wpada od razu na wybieg (gdy nie bylo fazy
## w krzakach - np. sygnal przyszedl prosto z testu).
func run_through(run: Rect2, seconds: float) -> void:
	_run = run
	if _exits.is_empty():
		_exits = [{"fence": Vector2(run.position.x + 80.0, run.end.y + 90.0),
				"bush": Vector2(run.position.x - 60.0, run.end.y + 190.0)}]
	var exit: Dictionary = _exits[randi() % _exits.size()]
	stand_at_fence(run, exit["fence"], _random_spot(), _exits)
	enter_run(seconds)


## Stara sciezka 12.17: lis zawrocony bez fazy w krzakach.
func sniff_and_leave(run: Rect2) -> void:
	run_through(run, 1.0)
	_leaping = false
	position = _fence_point
	phase = Phase.AT_FENCE
	_turn_back()


# --- wejscie i wyjscie ----------------------------------------------------


func _jump_in() -> void:
	phase = Phase.ENTER
	_dust.emitting = true
	_leap(_inside_point, 0.6, 85.0, func() -> void:
		phase = Phase.HUNT
		input_pickable = true
		_hunt_time = 0.0
		_heading = (_random_spot() - position).angle()
		_speed = RUN_SPEED * 0.5
		_pick_target()
		_refresh_counter()
		if _pending_kills > 0:
			var kills := _pending_kills
			_pending_kills = 0
			_on_caught(kills)
		if not _pending_breeds.is_empty():
			var breeds := _pending_breeds
			_pending_breeds = []
			_on_victims(breeds))


func _turn_back() -> void:
	phase = Phase.TURN_BACK
	input_pickable = false
	_refresh_counter()
	# Weszy i drapie pod plotem, potem odwraca sie i wraca do krzakow.
	_wait_left = 1.6
	_dig = 1.0


## Koniec wizyty - z przegonienia, psa, czasu albo konca lupu.
func leave() -> void:
	if phase == Phase.LEAVE or phase == Phase.DEAD or phase == Phase.TURN_BACK:
		return
	if phase == Phase.LURK or phase == Phase.APPROACH or phase == Phase.AT_FENCE:
		_turn_back()
		return
	phase = Phase.LEAVE
	input_pickable = false
	_refresh_counter()
	_dust.emitting = true
	var exit := _nearest_exit(position)
	var fence: Vector2 = exit.get("fence", position + Vector2(0, 200))
	var bush: Vector2 = exit.get("bush", fence + Vector2(0, 120))
	# Biegnie do plotu, przeskakuje go i znika w krzakach.
	var to_fence := Vector2(clampf(position.x, _run.position.x + 40.0, _run.end.x - 40.0),
			lerpf(position.y, fence.y, 0.55))
	_leap(to_fence, clampf(position.distance_to(to_fence) / 700.0, 0.25, 0.6), 30.0,
			func() -> void:
				_leap(Vector2(to_fence.x, fence.y), 0.5, 80.0, func() -> void:
					_bush_spot = bush
					_vanish_into(bush, 260.0)))


## Biegnie do krzaka i znika za nim.
func _vanish_into(spot: Vector2, speed: float) -> void:
	_target = spot
	_heading = (spot - position).angle()
	_speed = speed
	_approach_speed = speed
	_bush_spot = spot
	phase = Phase.LEAVE
	var fade := create_tween()
	fade.tween_interval(maxf(0.2, position.distance_to(spot) / speed - 0.3))
	fade.tween_property(_rig, "modulate:a", 0.0, 0.45)
	fade.tween_callback(queue_free)


func _nearest_exit(from: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for exit: Dictionary in _exits:
		var fence: Vector2 = exit["fence"]
		var d := absf(fence.y - from.y) + absf(fence.x - from.x) * 0.3
		if d < best_d:
			best_d = d
			best = exit
	return best


# --- petla -----------------------------------------------------------


func _process(delta: float) -> void:
	_clock += delta
	if phase == Phase.DEAD:
		return
	var before := position
	if _leaping:
		_advance_leap(delta)
	else:
		match phase:
			Phase.LURK:
				_do_lurk(delta)
			Phase.APPROACH:
				_steer_to(_fence_point, _approach_speed, delta)
				if position.distance_to(_fence_point) < 12.0:
					_arrive_at_fence()
			Phase.AT_FENCE:
				_speed = move_toward(_speed, 0.0, ACCEL * delta)
			Phase.TURN_BACK:
				_do_turn_back(delta)
			Phase.HUNT:
				_do_hunt(delta)
			Phase.LEAVE:
				if _bush_spot != Vector2.ZERO:
					_steer_to(_bush_spot, _approach_speed, delta)
	var moved := position.distance_to(before)
	_apply_pose(delta, false, moved)


func _do_lurk(delta: float) -> void:
	_lurk_left -= delta
	_speed = 0.0
	# Co chwile wychyla pysk zza krzaka i chowa z powrotem.
	_peek_left -= delta
	if _peek_left <= 0.0:
		_peek_left = randf_range(1.8, 3.6)
		var out := _bush_spot + Vector2(_facing * randf_range(16.0, 30.0), 0.0)
		_peek = create_tween()
		_peek.tween_property(self, "position", out, 0.35).set_trans(Tween.TRANS_SINE)
		_peek.tween_interval(randf_range(0.4, 0.9))
		_peek.tween_property(self, "position", _bush_spot, 0.4).set_trans(Tween.TRANS_SINE)
	if _lurk_left <= 0.0:
		if _peek != null and _peek.is_valid():
			_peek.kill()
		phase = Phase.APPROACH
		_crouch = 0.4
		_heading = (_fence_point - position).angle()


func _arrive_at_fence() -> void:
	position = _fence_point
	phase = Phase.AT_FENCE
	_speed = 0.0
	_set_facing(1.0 if _inside_point.x >= position.x else -1.0)
	match _verdict:
		"enter":
			_jump_in()
		"repel":
			_turn_back()
	_verdict = ""


func _do_turn_back(delta: float) -> void:
	if _wait_left > 0.0:
		_wait_left -= delta
		_speed = 0.0
		if _wait_left <= 0.0:
			_dig = 0.0
			_crouch = 0.0
			_vanish_into(_bush_spot, TROT_SPEED * 1.4)
			phase = Phase.TURN_BACK
		return
	_steer_to(_bush_spot, _approach_speed, delta)


func _do_hunt(delta: float) -> void:
	_hunt_time += delta
	_life -= delta
	# Wizyta skonczona w grze, a scena o tym nie wie - wychodzimy sami.
	if _life <= 0.0 or (_hunt_time > 0.4 and Game.state != null \
			and Game.state.fox_visit_left <= 0.0):
		leave()
		return
	if _pause_left > 0.0:
		_pause_left -= delta
		_speed = move_toward(_speed, 0.0, ACCEL * 2.0 * delta)
		_move(delta)
		return
	_steer_to(_target, RUN_SPEED, delta)
	if position.distance_to(_target) < 40.0:
		if randf() < 0.35:
			_pause_left = randf_range(0.25, 0.7)
		_pick_target()
	# Nie wybiega poza wybieg - odbija od brzegu nowym celem.
	if not _run.grow(-20.0).has_point(position):
		position = position.clamp(_run.position + Vector2(20, 20), _run.end - Vector2(20, 20))
		_pick_target()


## Skreca w strone celu z ograniczona predkoscia obrotu i rozpedza sie.
## Przy ostrym zakrecie zwalnia - tak skreca zwierze, a nie samolot.
func _steer_to(target: Vector2, top_speed: float, delta: float) -> void:
	var to := target - position
	if to.length() < 1.0:
		_speed = move_toward(_speed, 0.0, ACCEL * delta)
		return
	var want := to.angle()
	_heading = rotate_toward(_heading, want, TURN_RATE * delta)
	var off := absf(angle_difference(_heading, want))
	var cap := top_speed * clampf(1.0 - off / PI * 0.8, 0.25, 1.0)
	# Hamuje przed celem, zeby nie przelatywal obok.
	cap = minf(cap, maxf(60.0, to.length() * 4.0))
	_speed = move_toward(_speed, cap, ACCEL * delta)
	_move(delta)


func _move(delta: float) -> void:
	var step := Vector2.from_angle(_heading) * _speed * delta
	position += step
	if absf(step.x) > 0.5 * delta * 60.0 and absf(cos(_heading)) > 0.25:
		_set_facing(signf(step.x))


func _pick_target() -> void:
	# Co drugi raz celuje w kure, nie w puste miejsce.
	var hens: Array[Node2D] = []
	var around: Array[Node] = get_parent().get_children() if get_parent() != null else []
	for node in around:
		if node is FarmChicken and not (node as FarmChicken).leaving:
			hens.append(node)
	if not hens.is_empty() and randf() < 0.55:
		var hen: Node2D = hens[randi() % hens.size()]
		_target = (hen.position + Vector2(randf_range(-30, 30), randf_range(-10, 10))) \
				.clamp(_run.position + Vector2(40, 40), _run.end - Vector2(40, 20))
	else:
		_target = _random_spot()


## Losowy punkt na wybiegu.
func _random_spot() -> Vector2:
	return Vector2(
			randf_range(_run.position.x + 60.0, _run.end.x - 60.0),
			randf_range(_run.position.y + _run.size.y * 0.2, _run.end.y - 30.0))


# --- skoki -------------------------------------------------------------


func _leap(to: Vector2, seconds: float, height: float, done: Callable = Callable()) -> void:
	_leaping = true
	_leap_from = position
	_leap_to = to
	_leap_t = 0.0
	_leap_dur = maxf(0.05, seconds)
	_leap_h = height
	_leap_done = done
	if absf(to.x - position.x) > 4.0:
		_set_facing(signf(to.x - position.x))


func _advance_leap(delta: float) -> void:
	_leap_t = minf(1.0, _leap_t + delta / _leap_dur)
	var t := _leap_t
	position = _leap_from.lerp(_leap_to, t * t * (3.0 - 2.0 * t))
	_lift = sin(PI * t) * _leap_h
	if _leap_t < 1.0:
		return
	_leaping = false
	_lift = 0.0
	_heading = (_leap_to - _leap_from).angle()
	# Ladowanie: tulow przysiada i sie prostuje.
	_body.scale = Vector2(1.1, 0.88)
	create_tween().tween_property(_body, "scale", Vector2.ONE, 0.16)
	if _leap_done.is_valid():
		var done := _leap_done
		_leap_done = Callable()
		done.call()


# --- poza --------------------------------------------------------------


func _set_facing(dir: float, instant: bool = false) -> void:
	if dir == 0.0:
		return
	_facing = signf(dir)
	if instant and _rig != null:
		_rig.scale.x = _facing


## Ustawia czesci lisa wedlug chodu. `moved` - przebyta droga w tej klatce.
func _apply_pose(delta: float, instant: bool, moved: float = 0.0) -> void:
	if _rig == null:
		return
	# Obrot przez splaszczenie: skala x przechodzi przez zero zamiast skoku.
	_rig.scale.x = _facing if instant else move_toward(_rig.scale.x, _facing,
			FACE_TURN_SPEED * delta)

	var gait := "stand"
	if _leaping:
		gait = "leap"
	elif moved > 0.4:
		gait = "gallop" if _speed > 210.0 else "trot"
	_gait = gait
	var stride := GALLOP_STRIDE if gait == "gallop" else TROT_STRIDE
	_gait_phase = fmod(_gait_phase + moved / stride * TAU, TAU * 100.0)
	var s := sin(_gait_phase)
	var c := cos(_gait_phase)

	# Kat "do przodu" lapy: + = stopa w strone pyska. Obrot sprajta jest
	# odwrotny (zgodnie z zegarem stopa idzie do tylu).
	var front_near := 0.0
	var front_far := 0.0
	var hind_near := 0.0
	var hind_far := 0.0
	var flex := 0.0
	var lift := 0.0
	var pitch := 0.0
	var head := 0.0
	var tail := sin(_clock * 2.2) * 0.12
	match gait:
		"gallop":
			# Zebrany (s = 1): przednie w tyl, tylne w przod, grzbiet w luk.
			# Wyciagniety (s = -1): przednie w przod, tylne w tyl, lot.
			var lag := sin(_gait_phase - 0.55)
			front_near = -s * GALLOP_LEG
			front_far = -lag * GALLOP_LEG
			hind_near = s * GALLOP_LEG
			hind_far = lag * GALLOP_LEG
			flex = s * GALLOP_FLEX
			lift = pow(maxf(0.0, -s), 1.3) * GALLOP_LIFT
			pitch = -c * 0.06
			head = s * 0.1
			tail = -0.15 + c * 0.22
		"trot":
			# Klus: lapy po przekatnej ida razem.
			front_near = s * TROT_LEG
			hind_far = s * TROT_LEG
			front_far = -s * TROT_LEG
			hind_near = -s * TROT_LEG
			flex = s * 0.03
			lift = absf(s) * 3.0
			head = absf(c) * 0.05
			tail = -0.05 + sin(_gait_phase * 0.5) * 0.12
		"leap":
			front_near = 0.95
			front_far = 0.8
			hind_near = -0.95
			hind_far = -0.8
			flex = -0.08
			pitch = -0.12 * cos(PI * _leap_t)
			tail = -0.3
	# Drapanie pod plotem: przednia lapa grzebie, glowa w dol.
	if _dig > 0.0 and gait == "stand":
		front_near = 0.5 + sin(_clock * 18.0) * 0.6
		head = 0.25
	# Czajenie: tulow nizej, glowa przy ziemi.
	var crouch_y := _crouch * 7.0
	if _crouch > 0.0 and gait == "stand":
		head = maxf(head, 0.18 * _crouch)
		front_near = -0.15 * _crouch
		hind_near = 0.25 * _crouch
		hind_far = 0.2 * _crouch

	var k := 1.0 if instant else clampf(delta * 18.0, 0.0, 1.0)
	_turn(_legs["front_near"], -front_near, k)
	_turn(_legs["front_far"], -front_far, k)
	_turn(_legs["hind_near"], -hind_near, k)
	_turn(_legs["hind_far"], -hind_far, k)
	_turn(_rear, -flex, k)
	_turn(_front, flex, k)
	_turn(_head, head, k)
	_turn(_tail, tail, k)
	_turn(_body, pitch, k)
	var body_y := FoxRigData.JOINT.y - FoxRigData.ORIGIN.y - lift - _lift + crouch_y
	_body.position.y = lerpf(_body.position.y, body_y, k)
	# Cien maleje, gdy lis jest w powietrzu.
	var air := clampf((_lift + lift) / 90.0, 0.0, 0.6)
	_shadow.scale = Vector2.ONE * (1.0 - air)
	_dust.emitting = gait == "gallop" and phase == Phase.HUNT


func _turn(node: Node2D, angle: float, k: float) -> void:
	node.rotation = lerpf(node.rotation, angle, k)


# --- dotyk ------------------------------------------------------------


func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	var touch := event as InputEventScreenTouch
	if touch == null or phase != Phase.HUNT:
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


## Trafienie palcem. Liczenie trafien nalezy do Game - scena tylko zglasza.
## Trafiony lis odskakuje w bok i ucieka w inne miejsce wybiegu.
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
	if phase != Phase.HUNT or _leaping:
		return
	var side := Vector2(randf_range(120.0, 200.0) * (1.0 if randf() < 0.5 else -1.0),
			randf_range(-60.0, 60.0))
	var spot := (position + side).clamp(_run.position + Vector2(40, 40), _run.end - Vector2(40, 20))
	_leap(spot, 0.28, 42.0, func() -> void:
		_speed = RUN_SPEED
		_target = _random_spot())


# --- napasc i efekty ----------------------------------------------------


## Lis dopadl kure: krew, glowy, wstrzas i skok. Piora sypia sie osobno,
## w kolorze rasy ofiary (_on_victims). NIE konczy wizyty.
func _on_caught(count: int) -> void:
	if phase == Phase.ENTER or phase == Phase.AT_FENCE or phase == Phase.APPROACH:
		_pending_kills += count
		return
	if phase != Phase.HUNT:
		return
	_blood.emitting = true
	_spill_blood(count)
	_pop_heads(count)
	var farm := get_parent().get_parent() as Node2D if get_parent() != null else null
	if farm != null:
		var base := farm.position
		var shake := create_tween()
		for i in 4:
			shake.tween_property(farm, "position",
					base + Vector2(randf_range(-10.0, 10.0), randf_range(-7.0, 7.0)), 0.05)
		shake.tween_property(farm, "position", base, 0.08)
	if not _leaping:
		var pounce := position + Vector2(_facing * 70.0, randf_range(-14.0, 14.0))
		pounce = pounce.clamp(_run.position + Vector2(30, 30), _run.end - Vector2(30, 10))
		_leap(pounce, 0.3, 46.0, func() -> void:
			_pause_left = 0.35
			_pick_target())


## Fontanna piór w kolorach ofiar. Jedna fontanna na zabita kure.
func _on_victims(breeds: Array) -> void:
	if phase == Phase.ENTER or phase == Phase.AT_FENCE or phase == Phase.APPROACH:
		_pending_breeds.append_array(breeds)
		return
	if phase != Phase.HUNT:
		return
	var first := true
	for breed_id in breeds:
		var colors := _feather_colors(String(breed_id))
		if first:
			_color_feathers(_feathers, colors)
			_feathers.restart()
			_feathers.emitting = true
			first = false
			continue
		var extra := _feathers.duplicate() as CPUParticles2D
		_color_feathers(extra, colors)
		add_child(extra)
		extra.position = _feathers.position + Vector2(randf_range(-30, 30), 0)
		extra.emitting = true
		var gone := extra.create_tween()
		gone.tween_interval(extra.lifetime + 0.5)
		gone.tween_callback(extra.queue_free)


static func _feather_colors(breed_id: String) -> Array[Color]:
	var out: Array[Color] = []
	for hex in GameData.breed(breed_id).get("feather_colors", ["#FFFFFF", "#EFE6D6"]):
		out.append(Color.from_string(String(hex), Color.WHITE))
	if out.is_empty():
		out.append(Color.WHITE)
	return out


## Kolory piór: losowo z barw rasy, pod koniec zycia piora bledna.
static func _color_feathers(particles: CPUParticles2D, colors: Array[Color]) -> void:
	var start := Gradient.new()
	start.offsets = PackedFloat32Array([0.0, 1.0])
	start.colors = PackedColorArray([colors[0], colors[colors.size() - 1]])
	if colors.size() > 2:
		start.add_point(0.5, colors[1])
	particles.color_initial_ramp = start
	particles.color = Color.WHITE


## Urwane glowy wylatuja z miejsca napasci i laduja na wybiegu.
func _pop_heads(count: int) -> void:
	var host: Node = _decals if _decals != null else get_parent()
	if host == null:
		return
	for i in mini(maxi(1, count), HEADS_MAX):
		var head := Sprite2D.new()
		head.texture = HEAD
		head.z_index = 1
		head.position = position + Vector2(randf_range(-20.0, 20.0), randf_range(-30.0, -10.0))
		head.scale = Vector2.ONE * randf_range(0.56, 0.76)
		host.add_child(head)
		var away := head.position + Vector2(randf_range(-260.0, 260.0), randf_range(40.0, 120.0))
		var peak := head.position.y - randf_range(90.0, 170.0)
		var flight := randf_range(0.45, 0.7)
		var spin := head.create_tween()
		spin.tween_property(head, "rotation", randf_range(-9.0, 9.0), flight)
		var arc := head.create_tween()
		arc.tween_property(head, "position:x", away.x, flight).set_trans(Tween.TRANS_LINEAR)
		var up := head.create_tween()
		up.tween_property(head, "position:y", peak, flight * 0.45) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		up.tween_property(head, "position:y", away.y, flight * 0.55) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		up.tween_property(head, "scale:y", head.scale.y * 0.72, 0.1)
		up.tween_interval(SPLAT_SECONDS * 0.4)
		up.tween_property(head, "modulate:a", 0.0, SPLAT_SECONDS * 0.6)
		up.tween_callback(head.queue_free)


## Plamy krwi zostaja na wybiegu POD zwierzetami i powoli znikaja.
func _spill_blood(count: int) -> void:
	var host: Node = _decals if _decals != null else get_parent()
	if host == null:
		return
	for i in mini(maxi(1, count), SPLATS_MAX):
		var splat := Sprite2D.new()
		splat.texture = SPLAT
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


## Pies dopadl lisa: lis zostaje rozszarpany na miejscu.
func _torn_apart() -> void:
	if phase == Phase.DEAD:
		return
	phase = Phase.DEAD
	_leaping = false
	set_process(false)
	input_pickable = false
	_refresh_counter()
	_dust.emitting = false
	_feathers.emitting = true
	_blood.emitting = true
	_spill_blood(SPLATS_MAX)
	_fling_scraps()
	var host: Node = _decals if _decals != null else get_parent()
	if host != null:
		var pool := Sprite2D.new()
		pool.texture = SPLAT
		pool.z_index = 0
		pool.position = position + Vector2(0, 6)
		pool.rotation = randf_range(-0.12, 0.12)
		pool.scale = Vector2(3.6, 0.8)
		pool.modulate = Color(0.78, 0.08, 0.1, 0.0)
		host.add_child(pool)
		var soak := pool.create_tween()
		soak.tween_property(pool, "modulate:a", 0.92, 0.18)
		soak.tween_interval(SPLAT_SECONDS * 0.5)
		soak.tween_property(pool, "modulate:a", 0.0, SPLAT_SECONDS * 0.5)
		soak.tween_callback(pool.queue_free)
	# Lis osuwa sie plasko na trawe: splaszczenie, przechyl, ciemniejsze futro.
	var fall := create_tween()
	fall.set_parallel(true)
	fall.tween_property(_rig, "rotation", 0.12 * _facing, 0.22)
	fall.tween_property(_rig, "scale", Vector2(1.2 * _facing, 0.34), 0.22) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fall.tween_property(_rig, "modulate", Color(0.62, 0.36, 0.34), 0.4)
	fall.set_parallel(false)
	fall.tween_interval(1.6)
	fall.tween_property(_rig, "modulate:a", 0.0, 1.4)
	fall.tween_callback(queue_free)


## Strzepy futra rozrzucone po trawie.
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
		var away := scrap.position + Vector2(randf_range(-190.0, 190.0), randf_range(10.0, 90.0))
		var fly := scrap.create_tween()
		fly.set_parallel(true)
		fly.tween_property(scrap, "position", away, 0.4) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		fly.tween_property(scrap, "rotation", scrap.rotation + randf_range(-6.0, 6.0), 0.4)
		fly.set_parallel(false)
		fly.tween_interval(SPLAT_SECONDS * 0.4)
		fly.tween_property(scrap, "modulate:a", 0.0, SPLAT_SECONDS * 0.6)
		fly.tween_callback(scrap.queue_free)


## Rig - do testow (polozenie zwlok, skala).
func rig() -> Node2D:
	return _rig
