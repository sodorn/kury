extends Node2D
## Mapa gospodarstwa. Swiat ma 1080 x 2400 jednostek; na ekranie widac
## jego srodkowy wycinek (wysokosc zalezy od proporcji telefonu).
## Budynki, drzewa i krzaki stoja w farm.tscn, wiec widac je w edytorze.
## Kury i jaja dokladane sa w trakcie gry, bo ich liczba zalezy od stanu gry.

const WORLD_HEIGHT := 2400.0
## Obszar, po ktorym chodza kury i na ktorym ladują jaja (wnetrze plotu).
const RUN_AREA := Rect2(190, 1160, 700, 300)
const CHICKEN_SCENE: PackedScene = preload("res://scenes/farm/farm_chicken.tscn")
const EGG_SCENE: PackedScene = preload("res://scenes/farm/ground_egg.tscn")

@onready var _objects: Node2D = $Objects


func _ready() -> void:
	for hen: Chicken in Game.state.chickens:
		_add_hen(hen)
	for i in Game.state.eggs_on_ground:
		_add_egg()
	Events.hen_added.connect(_add_hen)
	Events.eggs_laid.connect(_on_eggs_laid)
	get_viewport().size_changed.connect(_center_world)
	_center_world()


func _center_world() -> void:
	position.y = (get_viewport_rect().size.y - WORLD_HEIGHT) * 0.5


func _add_hen(hen: Chicken) -> void:
	var node: FarmChicken = CHICKEN_SCENE.instantiate()
	_objects.add_child(node)
	node.setup(hen.breed_id, RUN_AREA)


func _on_eggs_laid(count: int) -> void:
	for i in count:
		_add_egg()


## Jajko pojawia sie obok losowej kury, a jesli stada nie ma — gdziekolwiek na wybiegu.
func _add_egg() -> void:
	var node: GroundEgg = EGG_SCENE.instantiate()
	_objects.add_child(node)
	node.position = _egg_position()


func _egg_position() -> Vector2:
	var hens: Array[Node] = []
	for child in _objects.get_children():
		if child is FarmChicken:
			hens.append(child)
	if hens.is_empty():
		return Vector2(
			randf_range(RUN_AREA.position.x, RUN_AREA.end.x),
			randf_range(RUN_AREA.position.y, RUN_AREA.end.y))
	var hen: Node2D = hens[randi() % hens.size()]
	var spot := hen.position + Vector2(randf_range(-70.0, 70.0), randf_range(-24.0, 36.0))
	return Vector2(
		clampf(spot.x, RUN_AREA.position.x, RUN_AREA.end.x),
		clampf(spot.y, RUN_AREA.position.y, RUN_AREA.end.y))
