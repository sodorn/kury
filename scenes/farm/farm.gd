extends Node2D
## Mapa gospodarstwa. Swiat ma 1080 x 2400 jednostek; na ekranie widac
## jego srodkowy wycinek (wysokosc zalezy od proporcji telefonu).
##
## Budynki, drzewa i krzaki stoja w farm.tscn, wiec widac je w edytorze.
## Zywy inwentarz (kury, pisklęta, jaja, zwloki) doklada sie w trakcie gry.
## Zamiast nasluchiwac pojedynczych zdarzen, scena co chwile porownuje sie
## ze stanem gry i doklada albo zabiera to, co trzeba. Dzieki temu wyglada
## poprawnie takze po wczytaniu zapisu i po nadrobieniu czasu offline.

const WORLD_HEIGHT := 2400.0
## Co ile sekund porownywac scene ze stanem gry.
const SYNC_SECONDS := 0.4

const CHICKEN_SCENE: PackedScene = preload("res://scenes/farm/farm_chicken.tscn")
const EGG_SCENE: PackedScene = preload("res://scenes/farm/ground_egg.tscn")
const CORPSE_SCENE: PackedScene = preload("res://scenes/farm/farm_corpse.tscn")
const FOX_SCENE: PackedScene = preload("res://scenes/farm/fox.tscn")

var _sync_left := 0.0
## Obszar, po ktorym chodza kury. Czytany z balance.json, zeby symulacja
## (kladzie zwloki) i scena uzywaly tych samych wspolrzednych.
var _run := Rect2()

@onready var _objects: Node2D = $Objects


func _ready() -> void:
	_run = Simulation.run_area()
	get_viewport().size_changed.connect(_center_world)
	Events.fox_arrived.connect(_on_fox_arrived)
	_center_world()
	_sync_livestock()


func _process(delta: float) -> void:
	_sync_left -= delta
	if _sync_left <= 0.0:
		_sync_left = SYNC_SECONDS
		_sync_livestock()


func _center_world() -> void:
	position.y = (get_viewport_rect().size.y - WORLD_HEIGHT) * 0.5


## Doprowadza scene do zgodnosci ze stanem gry.
func _sync_livestock() -> void:
	if Game.state == null:
		return
	var healthy := {}
	var sick := {}
	var healthy_roosters := {}
	var sick_roosters := {}
	for hen: Chicken in Game.state.chickens:
		var bucket := {}
		if hen.is_rooster:
			bucket = sick_roosters if hen.sick else healthy_roosters
		else:
			bucket = sick if hen.sick else healthy
		bucket[hen.breed_id] = int(bucket.get(hen.breed_id, 0)) + 1
	var cap := int(GameData.balance().get("run", {}).get("max_visible_hens", 26))
	# Chore kury pokazujemy zawsze — to one wymagaja reakcji gracza. Koguty tez
	# zawsze: jest ich po jednym na rase, a od nich zalezy, czy stado niesie.
	var shown_sick := sick
	var always := _total(shown_sick) + _total(healthy_roosters) + _total(sick_roosters)
	var budget := maxi(1, cap - always)
	_sync_animals(false, true, shown_sick, false)
	_sync_animals(false, true, sick_roosters, true)
	_sync_animals(false, false, healthy_roosters, true)
	_sync_animals(false, false, _clamp_visible(healthy, budget), false)
	_sync_animals(true, false, _clamp_visible(_chicks_by_breed(), maxi(4, cap / 3)), false)
	_sync_eggs(Game.ground_eggs_by_breed())
	_sync_corpses()


func _total(counts: Dictionary) -> int:
	var sum := 0
	for value: int in counts.values():
		sum += value
	return sum


## Przy duzym stadzie nie stawiamy wszystkiego — wybieg ma 1080 px szerokosci,
## a 150 kur to kasza. Liczby skalujemy proporcjonalnie, zostawiajac po jednej
## sztuce kazdej rasy, zeby zadna nie zniknela z widoku.
func _clamp_visible(counts: Dictionary, budget: int) -> Dictionary:
	var total := _total(counts)
	if total <= budget or total == 0:
		return counts
	var scaled := {}
	var used := 0
	for breed_id: String in counts:
		var share := int(floor(float(counts[breed_id]) * budget / total))
		scaled[breed_id] = maxi(1, share)
		used += int(scaled[breed_id])
	# Po zaokragleniu w gore moze wyjsc wiecej, niz wolno — scinamy nadwyzke.
	for breed_id: String in scaled:
		while used > budget and int(scaled[breed_id]) > 1:
			scaled[breed_id] = int(scaled[breed_id]) - 1
			used -= 1
	return scaled


func _chicks_by_breed() -> Dictionary:
	var counts := {}
	for chick: Chick in Game.state.chicks:
		counts[chick.breed_id] = int(counts.get(chick.breed_id, 0)) + 1
	return counts


## Ustawia liczbe kur (piskląt, chorych kur) kazdej rasy zgodnie ze stanem gry.
func _sync_animals(chicks: bool, sick: bool, wanted: Dictionary, roosters: bool) -> void:
	var present := {}
	for child in _objects.get_children():
		var animal := child as FarmChicken
		if animal == null or animal.is_chick != chicks or animal.is_sick != sick \
				or animal.is_rooster != roosters or animal.leaving:
			continue
		present[animal.breed_id] = int(present.get(animal.breed_id, 0)) + 1

	for breed_id: String in wanted:
		var missing := int(wanted[breed_id]) - int(present.get(breed_id, 0))
		for i in maxi(missing, 0):
			# Kura, ktora wlasnie zachorowala, ma zostac na swoim miejscu —
			# przestawiamy jej znacznik, zamiast podmieniac caly wezel.
			if not _flip_existing(breed_id, chicks, not sick, sick, roosters):
				_add_animal(breed_id, chicks, sick, roosters)

	for breed_id: String in present:
		var extra := int(present[breed_id]) - int(wanted.get(breed_id, 0))
		for i in maxi(extra, 0):
			_remove_animal(breed_id, chicks, sick, roosters)


## Przerabia zdrowa kure na chora bez podmiany wezla, zeby zostala na swoim
## miejscu na wybiegu.
##
## Tylko w te strone. Wczesniej dzialalo w obie i chore kury nigdy sie nie
## pokazywaly: najpierw uzgadnialismy chore (zdrowy wezel stawal sie chory),
## a zaraz potem uzgadnialismy zdrowe, ktorych nagle brakowalo — i ten sam
## wezel wracal do zdrowia. Wyzdrowienie obsluguje zwykle dodanie i usuniecie.
func _flip_existing(breed_id: String, chicks: bool, from_sick: bool, to_sick: bool,
		roosters: bool) -> bool:
	if chicks or from_sick == to_sick or not to_sick:
		return false
	for child in _objects.get_children():
		var animal := child as FarmChicken
		if animal == null or animal.leaving or animal.is_chick or animal.is_rooster != roosters:
			continue
		if animal.breed_id == breed_id and animal.is_sick == from_sick:
			animal.set_sick(to_sick)
			return true
	return false


func _add_animal(breed_id: String, chick: bool, sick: bool = false, rooster: bool = false) -> void:
	var node: FarmChicken = CHICKEN_SCENE.instantiate()
	_objects.add_child(node)
	node.setup(breed_id, _run, chick, sick, rooster)


func _remove_animal(breed_id: String, chick: bool, sick: bool, rooster: bool = false) -> void:
	for child in _objects.get_children():
		var animal := child as FarmChicken
		if animal == null or animal.leaving:
			continue
		if animal.breed_id == breed_id and animal.is_chick == chick and animal.is_sick == sick \
				and animal.is_rooster == rooster:
			animal.leave()
			return


## Jaja na wybiegu, osobno dla kazdej rasy — od rasy zalezy cena jajka.
func _sync_eggs(wanted: Dictionary) -> void:
	var present := {}
	for child in _objects.get_children():
		var egg := child as GroundEgg
		if egg == null or egg.collected:
			continue
		if not present.has(egg.breed_id):
			present[egg.breed_id] = [] as Array[Node]
		present[egg.breed_id].append(egg)

	for breed_id: String in wanted:
		var have: Array = present.get(breed_id, [])
		for i in maxi(int(wanted[breed_id]) - have.size(), 0):
			var node: GroundEgg = EGG_SCENE.instantiate()
			_objects.add_child(node)
			node.setup(breed_id, _egg_position())

	for breed_id: String in present:
		var extra: int = present[breed_id].size() - int(wanted.get(breed_id, 0))
		for i in maxi(extra, 0):
			present[breed_id][i].queue_free()


## Zwloki lezace na wybiegu. Pozycje trzyma stan gry, zeby po wznowieniu gry
## lezaly tam, gdzie gracz je zostawil.
func _sync_corpses() -> void:
	var nodes := {}
	for child in _objects.get_children():
		var corpse := child as FarmCorpse
		if corpse != null:
			nodes[corpse.get_instance_id()] = corpse
	var seen := {}
	for data: Corpse in Game.state.corpses:
		var found: FarmCorpse = null
		for corpse: FarmCorpse in nodes.values():
			if corpse.data == data:
				found = corpse
				break
		if found == null:
			found = CORPSE_SCENE.instantiate()
			_objects.add_child(found)
			found.setup(data)
		found.refresh()
		seen[found.get_instance_id()] = true
	for id: int in nodes:
		if not seen.has(id):
			nodes[id].queue_free()


## Lis wszedl na wybieg. Scena go pokazuje; o tym, czy cos zabierze,
## decyduje symulacja — albo gracz, jesli zdazy go przegonic.
func _on_fox_arrived(_count: int, seconds: float) -> void:
	var fox: Node2D = FOX_SCENE.instantiate()
	_objects.add_child(fox)
	fox.run_through(_run, seconds)


## Jajko pojawia sie obok losowej kury, a bez stada — gdziekolwiek na wybiegu.
func _egg_position() -> Vector2:
	var hens: Array[Node] = []
	for child in _objects.get_children():
		var animal := child as FarmChicken
		if animal != null and not animal.is_chick:
			hens.append(animal)
	if hens.is_empty():
		return Vector2(
			randf_range(_run.position.x, _run.end.x),
			randf_range(_run.position.y, _run.end.y))
	var hen: Node2D = hens[randi() % hens.size()]
	var spot := hen.position + Vector2(randf_range(-80.0, 80.0), randf_range(-24.0, 40.0))
	return Vector2(
		clampf(spot.x, _run.position.x, _run.end.x),
		clampf(spot.y, _run.position.y, _run.end.y))
