extends Node2D
## Mapa gospodarstwa. Swiat ma 1080 x 2400 jednostek; na ekranie widac
## jego srodkowy wycinek (wysokosc zalezy od proporcji telefonu).

const WORLD_HEIGHT := 2400.0
const BUILDING_SCENE: PackedScene = preload("res://scenes/farm/building.tscn")

## Obiekty sortowane po Y (budynki, drzewa, przedni plot; pozniej kury).
@onready var _objects: Node2D = $Objects


func _ready() -> void:
	for def: Dictionary in Config.buildings:
		var building: Building = BUILDING_SCENE.instantiate()
		_objects.add_child(building)
		building.setup(def)
	get_viewport().size_changed.connect(_center_world)
	_center_world()


func _center_world() -> void:
	position.y = (get_viewport_rect().size.y - WORLD_HEIGHT) * 0.5
