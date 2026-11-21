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
@onready var _continue_button: Button = $Sheet/Content/Choice/Continue
@onready var _new_button: Button = $Sheet/Content/Choice/NewFarm
@onready var _keypad: CodeKeypad = $Sheet/Content/Choice/CodeRow/Keypad
## Odpowiedz serwera pokazywana w samym okienku. Pasek z komunikatem lezy
## w drzewie PRZED ekranem powitalnym, wiec ekran go zaslania — gracz
## wpisywal kod, serwer odpowiadal "nie ma takiej farmy", a na wierzchu
## nie zmienialo sie nic.
@onready var _status: Label = $Sheet/Content/Choice/CodeRow/Status
@onready var _load_button: Button = $Sheet/Content/Choice/CodeRow/Load
@onready var _code_label: Label = $Sheet/Content/Created/Code
@onready var _play_button: Button = $Sheet/Content/Created/Play


func _ready() -> void:
	hide()
	_continue_button.pressed.connect(_close)
	_new_button.pressed.connect(_on_new_farm)
	_load_button.pressed.connect(_on_load)
	_play_button.pressed.connect(_close)
	_keypad.submitted.connect(func(_code: String) -> void: _on_load())
	Events.notice.connect(_on_notice)
	# Wczytanie farmy po kodzie konczy sie odpowiedzia serwera, a nie
	# nacisnieciem przycisku — dlatego czekamy na nia tutaj.
	Cloud.pulled.connect(_on_pulled)
	if Game.should_show_intro():
		_open()


var _confirm_wipe := false


func _open() -> void:
	Game.pause_simulation(true)
	_choice.show()
	_created.hide()
	# Gracz, ktory ma juz farme, widzi ten ekran raz. Nie wolno mu wtedy
	# podsunac "Nowej farmy" jako pierwszego przycisku — strata gospodarstwa
	# jednym dotknieciem bylaby nie do cofniecia.
	# "Graj dalej" dostaje kazdy, kto ma juz jakakolwiek farme — ekran wyskakuje
	# teraz przy kazdym uruchomieniu, wiec to on musi byc pierwszym przyciskiem.
	var has_farm := not Game.is_new_player
	_continue_button.visible = has_farm
	_continue_button.theme_type_variation = &"PrimaryButton" if has_farm else &""
	_new_button.theme_type_variation = &"" if has_farm else &"PrimaryButton"
	_new_button.text = tr("START_NEW_OTHER") if has_farm else tr("START_NEW")
	_confirm_wipe = false
	_keypad.visible = Cloud.is_enabled()
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
	# Przy istniejacej farmie pytamy drugi raz — tym razem wprost.
	if not Game.is_new_player and not _confirm_wipe:
		_confirm_wipe = true
		_new_button.text = tr("START_NEW_CONFIRM")
		return
	Game.start_new_farm()
	_code_label.text = Cloud.player_id
	_choice.hide()
	_created.show()


func _on_load() -> void:
	var code := _keypad.code()
	_load_button.disabled = true
	_show_status(tr("START_LOADING"))
	if not Game.restore_from_code(code):
		_load_button.disabled = false


## Kazdy komunikat gry przepisujemy do okienka, dopoki jest na wierzchu.
func _on_notice(text: String) -> void:
	if visible and _choice.visible:
		_show_status(text)


func _show_status(text: String) -> void:
	_status.text = text
	_status.visible = not text.is_empty()


## Serwer odpowiedzial na proste o farme spod wpisanego kodu.
func _on_pulled(payload: Dictionary, ok: bool, _for_player: String) -> void:
	if not visible or not _choice.visible:
		return
	_load_button.disabled = false
	if ok and not payload.is_empty():
		# Game juz podmienil stan; nie ma po co pokazywac kodu, gracz go zna.
		_close()


func _close() -> void:
	Game.mark_intro_seen()
	Game.pause_simulation(false)
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, FADE_TIME * 0.7)
	tween.tween_callback(hide)
