extends Control
## Dolny panel z informacjami o dotknietym budynku.
## Etap 2: nazwa, obrazek i opis. Zarzadzanie budynkiem dojdzie w kolejnych etapach.

const SLIDE_TIME := 0.22

var _tween: Tween
var _closing := false

@onready var _dim: ColorRect = $Dim
@onready var _sheet: PanelContainer = $Sheet
@onready var _title: Label = $Sheet/Content/Header/Title
@onready var _close: TextureButton = $Sheet/Content/Header/Close
@onready var _picture: TextureRect = $Sheet/Content/Body/Picture
@onready var _description: Label = $Sheet/Content/Body/Text/Description
@onready var _bottom_spacer: Control = $Sheet/Content/BottomSpacer


func _ready() -> void:
	hide()
	_dim.gui_input.connect(_on_dim_input)
	_close.pressed.connect(close)
	Events.building_tapped.connect(open)


func is_open() -> bool:
	return visible and not _closing


func open(building_id: String, picture: Texture2D = null) -> void:
	var def := GameData.building(building_id)
	if def.is_empty():
		return
	_title.text = tr(def.get("name", ""))
	_description.text = tr(def.get("desc", ""))
	_picture.texture = picture
	_bottom_spacer.custom_minimum_size.y = SafeArea.bottom_inset(get_viewport())

	_closing = false
	_kill_tween()
	show()
	modulate.a = 0.0
	# Jedna klatka, zeby kontenery policzyly wysokosc panelu przed animacja.
	await get_tree().process_frame
	var shown_y := size.y - _sheet.size.y
	_sheet.position.y = size.y
	_dim.modulate.a = 0.0
	modulate.a = 1.0
	_tween = create_tween().set_parallel()
	_tween.tween_property(_sheet, "position:y", shown_y, SLIDE_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_dim, "modulate:a", 1.0, SLIDE_TIME)


func close() -> void:
	if not visible or _closing:
		return
	_closing = true
	_kill_tween()
	_tween = create_tween().set_parallel()
	_tween.tween_property(_sheet, "position:y", size.y, SLIDE_TIME * 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_property(_dim, "modulate:a", 0.0, SLIDE_TIME * 0.7)
	_tween.chain().tween_callback(_finish_close)


func _finish_close() -> void:
	_closing = false
	hide()


func _kill_tween() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null


func _on_dim_input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	var click := event as InputEventMouseButton
	if touch != null and touch.pressed:
		close()
	elif click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		close()
