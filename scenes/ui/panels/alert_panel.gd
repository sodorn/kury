extends Control
## Okienko z ostrzezeniem. Uzywane tam, gdzie pasek komunikatow to za malo —
## choroba w stadzie wymaga reakcji, a pasek znika po kilku sekundach.
##
## Ostrzezenia ida w kolejce, zeby dwa naraz nie przykryly sie nawzajem.

const FADE_TIME := 0.26

var _queue: Array[Dictionary] = []
var _showing := false

@onready var _sheet: PanelContainer = $Sheet
@onready var _title: Label = $Sheet/Content/Title
@onready var _message: Label = $Sheet/Content/Message
@onready var _close: Button = $Sheet/Content/Close


func _ready() -> void:
	hide()
	_close.pressed.connect(_on_close)
	Events.alert.connect(_enqueue)


func _enqueue(title: String, message: String) -> void:
	_queue.append({"title": title, "message": message})
	if not _showing:
		_show_next()


func _show_next() -> void:
	if _queue.is_empty():
		_showing = false
		return
	_showing = true
	var entry: Dictionary = _queue.pop_front()
	_title.text = String(entry["title"])
	_message.text = String(entry["message"])
	show()
	modulate.a = 0.0
	_sheet.scale = Vector2(0.88, 0.88)
	_sheet.pivot_offset = _sheet.size * 0.5
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "modulate:a", 1.0, FADE_TIME)
	tween.tween_property(_sheet, "scale", Vector2.ONE, FADE_TIME * 1.4) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_close() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, FADE_TIME * 0.7)
	tween.tween_callback(hide)
	tween.tween_callback(_show_next)
