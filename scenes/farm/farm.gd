extends Node2D
## Mapa gospodarstwa. Swiat ma 1080 x 2400 jednostek; na ekranie widac
## jego srodkowy wycinek (wysokosc zalezy od proporcji telefonu).
## Budynki, drzewa i krzaki sa ustawione w farm.tscn, wiec widac je w edytorze.

const WORLD_HEIGHT := 2400.0


func _ready() -> void:
	get_viewport().size_changed.connect(_center_world)
	_center_world()


func _center_world() -> void:
	position.y = (get_viewport_rect().size.y - WORLD_HEIGHT) * 0.5
