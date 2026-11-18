extends Node2D
## Lis przebiegajacy przez wybieg. Sama animacja — stado zmniejsza symulacja,
## a wybieg zabiera kury przy nastepnym porownaniu ze stanem gry.

## Ile sekund zajmuje przebiegniecie przez caly wybieg.
const CROSS_SECONDS := 2.6
## Ile lis stoi w srodku wybiegu, zeby gracz go zauwazyl.
const PAUSE_SECONDS := 0.9

@onready var _sprite: Sprite2D = $Sprite


## Wpuszcza lisa z losowej strony, przeprowadza go przez wybieg i usuwa wezel.
func run_through(run: Rect2) -> void:
	var from_left := randf() < 0.5
	var y := randf_range(run.position.y + run.size.y * 0.35, run.end.y)
	var start_x := run.position.x - 260.0 if from_left else run.end.x + 260.0
	var end_x := run.end.x + 260.0 if from_left else run.position.x - 260.0
	var middle_x := run.get_center().x
	position = Vector2(start_x, y)
	_sprite.flip_h = not from_left

	var tween := create_tween()
	tween.tween_property(self, "position:x", middle_x, CROSS_SECONDS * 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# Przystanek w srodku: lis rozglada sie i skubie lup.
	tween.tween_property(_sprite, "rotation", 0.12, PAUSE_SECONDS * 0.5) \
			.set_trans(Tween.TRANS_SINE)
	tween.tween_property(_sprite, "rotation", 0.0, PAUSE_SECONDS * 0.5) \
			.set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "position:x", end_x, CROSS_SECONDS * 0.7) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)
