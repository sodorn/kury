class_name Building
extends Area2D
## Budynek na mapie. Poczatek wezla (0,0) lezy u podstawy budynku,
## dzieki czemu sortowanie po Y dziala naturalnie.
## Grafike, pozycje i obszar dotyku ustawia sie w scenie farm.tscn,
## wiec widac je w edytorze.
## Teksty i parametry pochodza z data/buildings.json, dopasowane po `building_id`.

## Maksymalny ruch palca (px ekranu), przy ktorym dotyk liczy sie jako tapniecie.
const TAP_MAX_MOVE := 60.0

@export var building_id: String = ""

var _pressed_touch: int = -1
var _pressed_at := Vector2.ZERO
var _tween: Tween

@onready var _sprite: Sprite2D = $Sprite
@onready var _shape: CollisionShape2D = $Shape

## 13.0 (wlasciciel 26.11): poziom budynku w kolku przy budynku na mapie,
## zeby nie trzeba bylo otwierac panelu. Tylko budynki z poziomami.
const LEVELED := ["coop", "storage", "incubator"]
var _badge: Node2D
var _badge_label: Label


func _ready() -> void:
	if GameData.building(building_id).is_empty():
		push_error("Building '%s': brak wpisu o id '%s' w data/buildings.json" % [name, building_id])
	if _sprite.texture == null:
		push_error("Building '%s': brak grafiki w wezle Sprite" % name)
	if _shape.shape == null:
		push_error("Building '%s': brak ksztaltu obszaru dotyku w wezle Shape" % name)
	if building_id in LEVELED:
		_make_level_badge()
		Events.resources_changed.connect(_refresh_level_badge)
		_refresh_level_badge()


func _make_level_badge() -> void:
	_badge = Node2D.new()
	_badge.name = "LevelBadge"
	_badge.z_index = 5
	_badge.draw.connect(func() -> void:
		_badge.draw_circle(Vector2.ZERO, 30.0, Color("#5A3A1E"))
		_badge.draw_circle(Vector2.ZERO, 25.0, Color("#B7791F")))
	_badge_label = Label.new()
	_badge_label.size = Vector2(60, 60)
	_badge_label.position = Vector2(-30, -31)
	_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge_label.add_theme_font_size_override("font_size", 34)
	_badge_label.add_theme_color_override("font_color", Color.WHITE)
	var font: Font = load("res://assets/fonts/Baloo2-800.ttf") as Font
	if font != null:
		_badge_label.add_theme_font_override("font", font)
	_badge.add_child(_badge_label)
	add_child(_badge)
	# Lewy dolny rog grafiki budynku (gora bywa przykryta komunikatem albo
	# napisem "Budowa").
	var rect := _sprite.get_rect()
	var corner := _sprite.position + Vector2(rect.position.x, rect.end.y) * _sprite.scale
	_badge.position = corner + Vector2(44, -44)


func _refresh_level_badge() -> void:
	if _badge_label == null or Game.state == null:
		return
	_badge_label.text = str(Game.state.building_level(building_id) + 1)


func _process(_delta: float) -> void:
	# Poziom zmienia sie tez bez sygnalu (koniec budowy w tle) - porownanie
	# jednej liczby na klatke nic nie kosztuje.
	if _badge_label != null and Game.state != null \
			and _badge_label.text != str(Game.state.building_level(building_id) + 1):
		_refresh_level_badge()


## Numer pokazany w kolku (do testow).
func level_badge_text() -> String:
	return _badge_label.text if _badge_label != null else ""


func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	# Reagujemy tylko na dotyk. Mysz na PC jest zamieniana na dotyk
	# (Project Settings > Input Devices > Pointing > Emulate Touch From Mouse).
	var touch := event as InputEventScreenTouch
	if touch == null:
		return
	if touch.pressed:
		_pressed_touch = touch.index
		_pressed_at = touch.position
		_press_feedback()
	elif touch.index == _pressed_touch:
		_pressed_touch = -1
		# Puszczenie palca daleko od miejsca nacisniecia to przeciagniecie, nie tapniecie.
		if touch.position.distance_to(_pressed_at) <= TAP_MAX_MOVE:
			_bounce()
			Events.building_tapped.emit(building_id, _sprite.texture)


func _press_feedback() -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_sprite, "scale", Vector2(1.06, 0.94), 0.07)
	_tween.tween_property(_sprite, "scale", Vector2.ONE, 0.12)


func _bounce() -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_sprite, "scale", Vector2(0.95, 1.07), 0.08)
	_tween.tween_property(_sprite, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
