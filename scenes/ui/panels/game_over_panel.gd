extends Control
## GAME OVER (wlasciciel 25.11): pelnoekranowa plansza, gdy gry nie da sie
## kontynuowac — nie ma pary do rozrodu, a w kasie brakuje na nowa (warunek
## w Simulation.check_bankrupt). Jedyne wyjscie to nowa ferma pod tym samym
## kodem. Plansza lezy nad wszystkim i lapie kazde dotkniecie.

const FADE_TIME := 0.5

var _title: Label
var _body: Label
var _detail: Label
var _button: Button
var _picture: TextureRect
var _box: VBoxContainer


func _ready() -> void:
	name = "GameOverPanel"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	hide()
	Events.game_over.connect(_on_game_over)


func _build() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.07, 0.04, 0.03, 0.94)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 70)
	add_child(margin)

	_box = VBoxContainer.new()
	_box.name = "Content"
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_theme_constant_override("separation", 34)
	margin.add_child(_box)

	_title = Label.new()
	_title.name = "Title"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 150)
	_title.add_theme_color_override("font_color", Color("#E2452F"))
	_title.add_theme_color_override("font_outline_color", Color("#2A120C"))
	_title.add_theme_constant_override("outline_size", 22)
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	_title.add_theme_constant_override("shadow_offset_y", 10)
	_box.add_child(_title)

	_picture = TextureRect.new()
	_picture.name = "Picture"
	_picture.custom_minimum_size = Vector2(380, 300)
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_picture.texture = load("res://assets/sprites/animals/hen_dead.svg")
	_picture.modulate = Color(0.85, 0.8, 0.75)
	_box.add_child(_picture)

	_body = Label.new()
	_body.name = "Body"
	_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_size_override("font_size", 58)
	_body.add_theme_color_override("font_color", Color("#FFF3DC"))
	_box.add_child(_body)

	_detail = Label.new()
	_detail.name = "Detail"
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_theme_font_size_override("font_size", 34)
	_detail.add_theme_color_override("font_color", Color("#D9C4A6"))
	_box.add_child(_detail)

	_button = Button.new()
	_button.name = "Restart"
	_button.theme_type_variation = &"PrimaryButton"
	_button.custom_minimum_size = Vector2(0, 130)
	_button.pressed.connect(_on_restart)
	_box.add_child(_button)


func _on_game_over() -> void:
	_title.text = tr("GAMEOVER_TITLE")
	_body.text = tr("GAMEOVER_BODY")
	_detail.text = tr("GAMEOVER_DETAIL")
	_button.text = tr("GAMEOVER_RESTART")
	# Na wierzch wszystkiego, takze nad innymi okienkami.
	get_parent().move_child(self, -1)
	show()
	modulate.a = 0.0
	_title.pivot_offset = _title.size * 0.5
	_title.scale = Vector2(2.2, 2.2)
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "modulate:a", 1.0, FADE_TIME)
	tween.tween_property(_title, "scale", Vector2.ONE, FADE_TIME * 1.6) \
			.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	# Martwa kura kiwa sie powoli, jak tabliczka na wietrze.
	_picture.pivot_offset = _picture.custom_minimum_size * 0.5
	var sway := create_tween().set_loops()
	sway.tween_property(_picture, "rotation", 0.06, 1.6).set_trans(Tween.TRANS_SINE)
	sway.tween_property(_picture, "rotation", -0.06, 1.6).set_trans(Tween.TRANS_SINE)


func _on_restart() -> void:
	Game.restart_after_game_over()
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, FADE_TIME * 0.6)
	tween.tween_callback(hide)
