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
const DOG_SCENE: PackedScene = preload("res://scenes/farm/dog.tscn")
## Gdzie siedzi pies, gdy nic sie nie dzieje: pod kurnikiem, przy wybiegu.
const DOG_HOME := Vector2(196.0, 905.0)

## Plot na kolejnych poziomach obrony. Indeks = guard_level, wiec 0 to plot,
## ktory stoi od pierwszego dnia. Kazdy kolejny jest wyzszy; dol zostaje na
## tej samej linii trawy, bo offset liczymy z wysokosci tekstury.
const FENCES: Array[Texture2D] = [
	preload("res://assets/sprites/world/fence_front.svg"),
	preload("res://assets/sprites/world/fence_front_1.svg"),
	preload("res://assets/sprites/world/fence_front_2.svg"),
	preload("res://assets/sprites/world/fence_front_3.svg"),
	preload("res://assets/sprites/world/fence_front_4.svg"),
]
## Ile pikseli tekstury plotu wystaje PONIZEJ linii, na ktorej stoi sprajt.
const FENCE_FOOT := 6.0

## Budynki maja po trzy poziomy wygladu: zwykly, rozbudowany, przemyslowy.
## Mapa: nazwa wezla -> [tekstury] oraz progi poziomow rozbudowy.
const BUILDING_LOOKS := {
	"Coop": [
		preload("res://assets/sprites/buildings/coop.svg"),
		preload("res://assets/sprites/buildings/coop_2.svg"),
		preload("res://assets/sprites/buildings/coop_3.svg"),
	],
	"Incubator": [
		preload("res://assets/sprites/buildings/incubator.svg"),
		preload("res://assets/sprites/buildings/incubator_2.svg"),
		preload("res://assets/sprites/buildings/incubator_3.svg"),
	],
	"Storage": [
		preload("res://assets/sprites/buildings/storage.svg"),
		preload("res://assets/sprites/buildings/storage_2.svg"),
		preload("res://assets/sprites/buildings/storage_3.svg"),
	],
}
## Od ktorego poziomu rozbudowy budynek zmienia wyglad na kolejny.
const LOOK_STEPS := [3, 6]

var _sync_left := 0.0
## Obszar, po ktorym chodza kury. Czytany z balance.json, zeby symulacja
## (kladzie zwloki) i scena uzywaly tych samych wspolrzednych.
var _run := Rect2()

var _dog: FarmDog = null

@onready var _objects: Node2D = $Objects
@onready var _decals: Node2D = $Decals


func _ready() -> void:
	_run = Simulation.run_area()
	get_viewport().size_changed.connect(_center_world)
	Events.fox_lurking.connect(_on_fox_lurking)
	Events.fox_arrived.connect(_on_fox_arrived)
	Events.fox_repelled.connect(_on_fox_repelled)
	_center_world()
	_sync_livestock()
	_sync_dog()
	_sync_buildings()


func _process(delta: float) -> void:
	_sync_left -= delta
	if _sync_left <= 0.0:
		_sync_left = SYNC_SECONDS
		_sync_livestock()
		_sync_dog()
		_sync_buildings()


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


## Krzaki, z ktorych wychodzi lis, i punkty pod plotem. Dwa krzaki na
## polnoc od wybiegu (miedzy budynkami) i dwa na poludnie (przy magazynie
## i sklepie). Polnocny plot jest narysowany na trawie, poludniowy to sprajt
## FenceFront - stad rozne wysokosci.
const BUSHES := ["BushLeftTop", "BushRightTop", "BushLeftBottom", "BushRightBottom"]


## Dla kazdego krzaka: gdzie lis sie chowa, pod ktorym miejscem plotu staje
## i gdzie laduje po przeskoczeniu. Wspolrzedne swiata farmy.
func _fox_routes() -> Array[Dictionary]:
	var routes: Array[Dictionary] = []
	var fence_front := $Objects.get_node_or_null("FenceFront") as Node2D
	var south_y := (fence_front.position.y if fence_front != null else _run.end.y + 58.0) + 34.0
	var north_y := _run.position.y - 125.0
	for bush_name: String in BUSHES:
		var bush := $Objects.get_node_or_null(bush_name) as Node2D
		if bush == null:
			continue
		var left := bush.position.x < _run.get_center().x
		var north := bush.position.y < _run.get_center().y
		var side := 1.0 if left else -1.0
		# Lis stoi tuz ZA krzakiem (mniejsze y = rysowany pod nim), z pyskiem
		# wystajacym w strone wybiegu. Znad krzaka widac uszy.
		var hide := Vector2(bush.position.x + side * 26.0, bush.position.y - 8.0)
		var fence_x := bush.position.x + side * randf_range(200.0, 330.0)
		var fence := Vector2(fence_x, north_y if north else south_y)
		var inside := Vector2(fence_x + side * randf_range(30.0, 90.0),
				_run.position.y + 40.0 if north else _run.end.y - 45.0)
		routes.append({"bush": hide, "fence": fence, "inside": inside})
	return routes


func _current_fox() -> FarmFox:
	for node in _objects.get_children():
		var fox := node as FarmFox
		if fox != null and fox.phase != FarmFox.Phase.DEAD \
				and fox.phase != FarmFox.Phase.LEAVE and fox.phase != FarmFox.Phase.TURN_BACK:
			return fox
	return null


func _new_fox() -> FarmFox:
	var fox: FarmFox = FOX_SCENE.instantiate()
	_objects.add_child(fox)
	fox.set_decals(_decals)
	return fox


## Lis wyszedl z krzakow. Pokazujemy go za losowym krzakiem; za `seconds`
## sekund stanie pod plotem i symulacja zdecyduje, czy wejdzie.
func _on_fox_lurking(seconds: float) -> void:
	if _current_fox() != null:
		return
	var routes := _fox_routes()
	if routes.is_empty():
		return
	var route: Dictionary = routes[randi() % routes.size()]
	var approach := float(GameData.balance().get("fox", {}).get("approach_seconds", 4.0))
	_new_fox().lurk(_run, route["bush"], route["fence"], route["inside"], routes,
			seconds, approach)


## Lis wszedl na wybieg. Jesli czail sie w krzakach - przeskakuje plot.
## Jesli nie (np. sygnal po wczytaniu gry) - pojawia sie pod plotem i skacze.
## Na wybiegu moze byc najwyzej JEDEN lis (wlasciciel mial kiedys trzy).
func _on_fox_arrived(_count: int, seconds: float) -> void:
	var fox := _current_fox()
	if fox != null and fox.phase == FarmFox.Phase.HUNT:
		return
	if fox == null:
		var routes := _fox_routes()
		if routes.is_empty():
			return
		var route: Dictionary = routes[randi() % routes.size()]
		fox = _new_fox()
		fox.stand_at_fence(_run, route["fence"], route["inside"], routes)
	fox.enter_run(seconds)
	if _dog != null:
		_dog.chase(fox, _run)


## Pies pojawia sie na podworku, gdy tylko gracz go kupi, i znika razem
## z farma, na ktorej go nie ma. Wlasciciel kupil psa i go nie zobaczyl —
## bo wczesniej pies istnial wylacznie jako liczba w panelu.
func _sync_dog() -> void:
	if Game.state == null:
		return
	var powinien := Game.state.dog_level > 0
	if powinien == (_dog != null and is_instance_valid(_dog)):
		if _dog != null and is_instance_valid(_dog):
			_dog.show_breed(Game.state.dog_level)
		return
	if powinien:
		_dog = DOG_SCENE.instantiate()
		_dog.position = DOG_HOME
		_objects.add_child(_dog)
		_dog.show_breed(Game.state.dog_level)
	elif _dog != null:
		_dog.queue_free()
		_dog = null


## Sprzatanie po wczytaniu gry: zaden lis nie przezywa przeladowania.
func clear_foxes() -> void:
	for node in _objects.get_children():
		if node is FarmFox:
			node.queue_free()


## Plot zawrocil lisa. Jesli lis stoi pod plotem - drapie i wraca w krzaki.
## Jesli nie bylo go widac (np. po powrocie do gry), pokazujemy krotka
## scenke: lis podchodzi pod plot i odchodzi. Bez tego zakup plotu wyglada,
## jakby nic nie zmienil.
func _on_fox_repelled() -> void:
	var fox := _current_fox()
	if fox != null:
		fox.repel()
		return
	var routes := _fox_routes()
	if routes.is_empty():
		return
	var route: Dictionary = routes[randi() % routes.size()]
	fox = _new_fox()
	fox.lurk(_run, route["bush"], route["fence"], route["inside"], routes, 2.2, 1.6)
	fox.repel()


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


## Ustawia wyglad plotu i budynkow pod aktualne poziomy rozbudowy. Tanie:
## przypisanie tej samej tekstury drugi raz nic nie kosztuje, wiec mozna to
## wolac z tym samym rytmem co reszte synchronizacji sceny.
func _sync_buildings() -> void:
	if Game.state == null:
		return
	var fence := $Objects/FenceFront as Sprite2D
	if fence != null:
		var want: Texture2D = FENCES[clampi(Game.state.guard_level, 0, FENCES.size() - 1)]
		if fence.texture != want:
			fence.texture = want
			# Sprajt nie jest wysrodkowany, wiec wyzsza tekstura sama by
			# urosla w dol i zaklaby trawe. Przesuwamy ja o jej wysokosc.
			fence.offset.y = -(want.get_height() - FENCE_FOOT)
	for node_name: String in BUILDING_LOOKS:
		var building := $Objects.get_node_or_null(node_name)
		if building == null:
			continue
		var sprite := building.get_node_or_null("Sprite") as Sprite2D
		if sprite == null:
			continue
		var looks: Array = BUILDING_LOOKS[node_name]
		var level := Game.state.building_level(String(building.building_id))
		var tier := 0
		for step: int in LOOK_STEPS:
			if level >= step:
				tier += 1
		var texture: Texture2D = looks[mini(tier, looks.size() - 1)]
		if sprite.texture != texture:
			sprite.texture = texture
