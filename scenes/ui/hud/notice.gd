class_name Notice
extends PanelContainer
## Krotki komunikat u gory ekranu, np. "skonczyla sie pasza".
## Sam sie chowa; nowy komunikat zastepuje poprzedni.

const VISIBLE_SECONDS := 4.5
const FADE := 0.25

var _tween: Tween

@onready var _label: Label = $Text


func _ready() -> void:
	modulate.a = 0.0
	hide()
	Events.notice.connect(show_text)


func show_text(text: String) -> void:
	if text.is_empty():
		return
	_label.text = text
	show()
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, FADE)
	_tween.tween_interval(VISIBLE_SECONDS)
	_tween.tween_property(self, "modulate:a", 0.0, FADE)
	_tween.tween_callback(hide)
