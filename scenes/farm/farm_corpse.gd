class_name FarmCorpse
extends Node2D
## Padla kura lezaca na wybiegu. Z czasem blednie i zapada sie w trawe,
## az symulacja usunie ja ze stanu gry.
##
## Wezel nie trzyma zadnej logiki: pozycja i czas rozkladu siedza w modelu
## (Corpse), zeby po wznowieniu gry zwloki lezaly tam, gdzie padly.

## Jak mocno zwloki blakna na koniec rozkladu.
const FADE_TO := 0.15

var data: Corpse

@onready var _sprite: Sprite2D = $Sprite


## Przypisuje dane modelu i ustawia wezel na wybiegu.
func setup(corpse: Corpse) -> void:
	data = corpse
	position = corpse.position()
	var breed := GameData.breed(corpse.breed_id)
	# Lekki odcien rasy, zeby bylo widac, co padlo; grafika jest szaro-biala.
	var tint := String(breed.get("corpse_tint", ""))
	if not tint.is_empty():
		_sprite.modulate = Color(tint)
	_sprite.flip_h = randf() < 0.5
	refresh()


## Dostraja przezroczystosc do postepu rozkladu.
func refresh() -> void:
	if data == null:
		return
	var left := 1.0 - data.progress()
	_sprite.modulate.a = lerpf(FADE_TO, 1.0, left)
	# Pod koniec zwloki wtapiaja sie w ziemie.
	var squash := lerpf(0.82, 1.0, left)
	_sprite.scale = Vector2(1.0, squash)
