extends Control
## Ekran wygranej. Pokazuje sie raz, w chwili spelnienia warunku, i nie
## konczy gry — gracz moze zamknac okno i hodowac dalej.

const FADE_TIME := 0.3

@onready var _dim: ColorRect = $Dim
@onready var _sheet: PanelContainer = $Sheet
@onready var _title: Label = $Sheet/Content/Title
@onready var _message: Label = $Sheet/Content/Message
@onready var _button: Button = $Sheet/Content/Continue


func _ready() -> void:
	hide()
	_button.pressed.connect(_close)
	Events.game_won.connect(_on_game_won)


func _on_game_won(reason: String) -> void:
	_title.text = tr("WIN_TITLE")
	_message.text = tr("WIN_COLLECTION") if reason == "collection" else tr("WIN_MONEY")
	_button.text = tr("WIN_CONTINUE")
	show()
	modulate.a = 0.0
	_sheet.scale = Vector2(0.86, 0.86)
	_sheet.pivot_offset = _sheet.size * 0.5
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "modulate:a", 1.0, FADE_TIME)
	tween.tween_property(_sheet, "scale", Vector2.ONE, FADE_TIME) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _close() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, FADE_TIME * 0.7)
	tween.tween_callback(hide)
