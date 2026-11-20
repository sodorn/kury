extends Control
## Ekran powitalny. Pokazuje sie tylko wtedy, gdy na tym urzadzeniu nie ma
## jeszcze zadnego zapisu: albo zakladamy nowa farme, albo wracamy do swojej
## po kodzie przepisanym z innego telefonu.
##
## Ma dwa kroki. Pierwszy to wybor, drugi pokazuje swiezo wylosowany kod —
## osobny ekran, bo to jedyna rzecz, ktora gracz musi sobie gdzies zapisac,
## a komunikat na pasku znika po kilku sekundach.

const FADE_TIME := 0.3

@onready var _sheet: PanelContainer = $Sheet
@onready var _choice: VBoxContainer = $Sheet/Content/Choice
@onready var _created: VBoxContainer = $Sheet/Content/Created
@onready var _new_button: Button = $Sheet/Content/Choice/NewFarm
@onready var _code_field: LineEdit = $Sheet/Content/Choice/CodeRow/Code
@onready var _load_button: Button = $Sheet/Content/Choice/CodeRow/Load
@onready var _code_label: Label = $Sheet/Content/Created/Code
@onready var _play_button: Button = $Sheet/Content/Created/Play


func _ready() -> void:
	hide()
	_new_button.pressed.connect(_on_new_farm)
	_load_button.pressed.connect(_on_load)
	_play_button.pressed.connect(_close)
	_code_field.text_submitted.connect(func(_text: String) -> void: _on_load())
	# Wczytanie farmy po kodzie konczy sie odpowiedzia serwera, a nie
	# nacisnieciem przycisku — dlatego czekamy na nia tutaj.
	Cloud.pulled.connect(_on_pulled)
	if Game.is_new_player:
		_open()


func _open() -> void:
	Game.pause_simulation(true)
	_choice.show()
	_created.hide()
	_code_field.editable = Cloud.is_enabled()
	_load_button.disabled = not Cloud.is_enabled()
	show()
	modulate.a = 0.0
	_sheet.scale = Vector2(0.88, 0.88)
	_sheet.pivot_offset = _sheet.size * 0.5
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "modulate:a", 1.0, FADE_TIME)
	tween.tween_property(_sheet, "scale", Vector2.ONE, FADE_TIME * 1.3) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_new_farm() -> void:
	Game.start_new_farm()
	_code_label.text = Cloud.player_id
	_choice.hide()
	_created.show()


func _on_load() -> void:
	var code := _code_field.text
	_load_button.disabled = true
	if not Game.restore_from_code(code):
		_load_button.disabled = false


## Serwer odpowiedzial na proste o farme spod wpisanego kodu.
func _on_pulled(payload: Dictionary, ok: bool) -> void:
	if not visible or not _choice.visible:
		return
	_load_button.disabled = false
	if ok and not payload.is_empty():
		# Game juz podmienil stan; nie ma po co pokazywac kodu, gracz go zna.
		Game.is_new_player = false
		_close()


func _close() -> void:
	Game.is_new_player = false
	Game.pause_simulation(false)
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, FADE_TIME * 0.7)
	tween.tween_callback(hide)
