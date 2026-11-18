extends Node2D
## Mapa gospodarstwa. Swiat ma 1080 x 2400 jednostek; na ekranie widac
## jego srodkowy wycinek (wysokosc zalezy od proporcji telefonu).
##
## Budynki, drzewa i krzaki stoja w farm.tscn, wiec widac je w edytorze.
## Zywy inwentarz (kury, pisklęta, jaja) doklada sie w trakcie gry.
## Zamiast nasluchiwac pojedynczych zdarzen, scena co chwile porownuje sie
## ze stanem gry i doklada albo zabiera to, co trzeba. Dzieki temu wyglada
## poprawnie takze po wczytaniu zapisu i po nadrobieniu czasu offline.

const WORLD_HEIGHT := 2400.0
## Obszar, po ktorym chodza kury i na ktorym pojawiaja sie jaja (wnetrze plotu).
const RUN_AREA := Rect2(190, 1160, 700, 300)
## Co ile sekund porownywac scene ze stanem gry.
const SYNC_SECONDS := 0.4

const CHICKEN_SCENE: PackedScene = preload("res://scenes/farm/farm_chicken.tscn")
const EGG_SCENE: PackedScene = preload("res://scenes/farm/ground_egg.tscn")

var _sync_left := 0.0

@onready var _objects: Node2D = $Objects


func _ready() -> void:
	get_viewport().size_changed.connect(_center_world)
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
	_sync_animals(false, Game.state.hens_by_breed())
	_sync_animals(true, _chicks_by_breed())
	_sync_eggs(Game.state.eggs_on_ground)


func _chicks_by_breed() -> Dictionary:
	var counts := {}
	for chick: Chick in Game.state.chicks:
		counts[chick.breed_id] = int(counts.get(chick.breed_id, 0)) + 1
	return counts


## Ustawia liczbe kur (albo piskląt) kazdej rasy zgodnie ze stanem gry.
func _sync_animals(chicks: bool, wanted: Dictionary) -> void:
	var present := {}
	for child in _objects.get_children():
		var animal := child as FarmChicken
		if animal == null or animal.is_chick != chicks or animal.leaving:
			continue
		present[animal.breed_id] = int(present.get(animal.breed_id, 0)) + 1

	for breed_id: String in wanted:
		var missing := int(wanted[breed_id]) - int(present.get(breed_id, 0))
		for i in maxi(missing, 0):
			_add_animal(breed_id, chicks)

	for breed_id: String in present:
		var extra := int(present[breed_id]) - int(wanted.get(breed_id, 0))
		for i in maxi(extra, 0):
			_remove_animal(breed_id, chicks)


func _add_animal(breed_id: String, chick: bool) -> void:
	var node: FarmChicken = CHICKEN_SCENE.instantiate()
	_objects.add_child(node)
	node.setup(breed_id, RUN_AREA, chick)


func _remove_animal(breed_id: String, chick: bool) -> void:
	for child in _objects.get_children():
		var animal := child as FarmChicken
		if animal != null and animal.breed_id == breed_id and animal.is_chick == chick and not animal.leaving:
			animal.leave()
			return


func _sync_eggs(wanted: int) -> void:
	var eggs: Array[Node] = []
	for child in _objects.get_children():
		var egg := child as GroundEgg
		if egg != null and not egg.collected:
			eggs.append(egg)
	for i in maxi(wanted - eggs.size(), 0):
		var node: GroundEgg = EGG_SCENE.instantiate()
		_objects.add_child(node)
		node.position = _egg_position()
	for i in maxi(eggs.size() - wanted, 0):
		eggs[i].queue_free()


## Jajko pojawia sie obok losowej kury, a bez stada — gdziekolwiek na wybiegu.
func _egg_position() -> Vector2:
	var hens: Array[Node] = []
	for child in _objects.get_children():
		var animal := child as FarmChicken
		if animal != null and not animal.is_chick:
			hens.append(animal)
	if hens.is_empty():
		return Vector2(
			randf_range(RUN_AREA.position.x, RUN_AREA.end.x),
			randf_range(RUN_AREA.position.y, RUN_AREA.end.y))
	var hen: Node2D = hens[randi() % hens.size()]
	var spot := hen.position + Vector2(randf_range(-70.0, 70.0), randf_range(-24.0, 36.0))
	return Vector2(
		clampf(spot.x, RUN_AREA.position.x, RUN_AREA.end.x),
		clampf(spot.y, RUN_AREA.position.y, RUN_AREA.end.y))
