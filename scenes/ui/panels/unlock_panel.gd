extends Control
## Okienko "nowa rasa na fermie" (12.21: prawie caly ekran - wlasciciel 25.11).
## To samo okno pokazuje KARTE RASY z ekranu Osiagniec (`show_card`). Gratulacje, duzy
## malowany portret rasy (tools/gen_portraits.py), historia, ciekawostki
## sprawdzone w zrodlach i liczby ze sklepu. Zlota ramka, promienie, iskry.
##
## Odblokowania potrafia trafic sie po dwa naraz (gracz przekroczyl prog
## pieniedzy i liczbe kur w tej samej klatce), wiec rasy czekaja w kolejce
## i pokazuja sie jedna po drugiej.

const FADE_TIME := 0.32
## Pelny obrot promieni.
const SPIN_SECONDS := 26.0

var _queue: Array[String] = []
var _showing := false
## true = okno otwarte z Osiagniec (bez gratulacji, bez kolejki).
var _card_mode := false

@onready var _rays: TextureRect = $Rays
@onready var _sheet: PanelContainer = $Sheet
@onready var _portrait: TextureRect = $Sheet/Content/Frame/Portrait
@onready var _name: Label = $Sheet/Content/Name
@onready var _rarity: Label = $Sheet/Content/Rarity
@onready var _lore: Label = $Sheet/Content/Scroll/Text/Lore
@onready var _facts: Label = $Sheet/Content/Scroll/Text/Facts
@onready var _facts_title: Label = $Sheet/Content/Scroll/Text/FactsTitle
@onready var _stats: Label = $Sheet/Content/Scroll/Text/Stats
@onready var _scroll: ScrollContainer = $Sheet/Content/Scroll
@onready var _close: Button = $Sheet/Content/Close
@onready var _sparks: CPUParticles2D = $Sparks


func _ready() -> void:
	hide()
	_close.pressed.connect(_on_close)
	Events.breed_unlocked.connect(_enqueue)
	_style_frame()


## Zlota ramka wokol portretu. Budowana w kodzie, bo to jedyne miejsce
## w grze, ktore jej uzywa.
func _style_frame() -> void:
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color("#FFFCF5")
	frame.set_corner_radius_all(18)
	frame.set_border_width_all(12)
	frame.border_color = Color("#E8B64C")
	frame.set_content_margin_all(6)
	frame.shadow_color = Color(0.36, 0.25, 0.16, 0.35)
	frame.shadow_size = 10
	$Sheet/Content/Frame.add_theme_stylebox_override("panel", frame)
	var congrats := $Sheet/Content/Congrats as Label
	congrats.add_theme_color_override("font_color", Color("#D9902A"))
	congrats.add_theme_color_override("font_outline_color", Color("#FFF4D6"))
	congrats.add_theme_constant_override("outline_size", 10)


## Karta rasy z ekranu Osiagniec: ten sam wielki portret i opis, ale bez
## gratulacji.
func show_card(breed_id: String) -> void:
	_card_mode = true
	_fill(GameData.breed(breed_id))
	_open()


func _enqueue(breed_id: String) -> void:
	if not _queue.has(breed_id):
		_queue.append(breed_id)
	if not _showing:
		_show_next()


func _show_next() -> void:
	if _queue.is_empty():
		_showing = false
		return
	_showing = true
	_card_mode = false
	_fill(GameData.breed(_queue.pop_front()))
	_open()


func _open() -> void:
	get_parent().move_child(self, -1)
	show()
	modulate.a = 0.0
	_sheet.scale = Vector2(0.8, 0.8)
	_sheet.pivot_offset = _sheet.size * 0.5
	_rays.rotation = 0.0
	_sparks.emitting = true

	var tween := create_tween().set_parallel()
	tween.tween_property(self, "modulate:a", 1.0, FADE_TIME)
	tween.tween_property(_sheet, "scale", Vector2.ONE, FADE_TIME * 1.4) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var spin := create_tween().set_loops()
	spin.tween_property(_rays, "rotation", TAU, SPIN_SECONDS).from(0.0)


func _fill(breed: Dictionary) -> void:
	($Sheet/Content/Congrats as Label).text = tr("UNLOCK_CONGRATS")
	($Sheet/Content/Title as Label).text = tr("UNLOCK_TITLE")
	($Sheet/Content/Congrats as Label).visible = not _card_mode
	($Sheet/Content/Title as Label).visible = not _card_mode
	_close.text = tr("UNLOCK_CARD_CLOSE") if _card_mode else tr("UNLOCK_CLOSE")
	_rays.visible = not _card_mode
	_name.text = tr(breed.get("name", ""))
	_rarity.text = tr(breed.get("rarity", "")).to_upper()
	_lore.text = tr(breed.get("lore", ""))
	var facts: PackedStringArray = []
	for key: Variant in breed.get("facts", []):
		facts.append("•  " + tr(String(key)))
	_facts.text = "\n".join(facts)
	_facts.visible = not facts.is_empty()
	_facts_title.visible = _facts.visible
	_scroll.scroll_vertical = 0
	_stats.text = "%s\n%s" % [
		tr("UNLOCK_PRICE") % NumberFormat.money(float(breed.get("price", 0))),
		tr("UNLOCK_EGG" if breed.get("rarity", "") == "RARITY_COMMON" else "UNLOCK_EGG_HATCH") % [
			NumberFormat.small_money(float(breed.get("egg_value", 0))),
			NumberFormat.duration(float(breed.get("egg_seconds", 0)) / GameData.time_scale())],
	]
	_portrait.texture = _breed_image(breed)


## Malowany portret rasy; bez niego zdjecie, a na koniec rysunek z wybiegu.
func _breed_image(breed: Dictionary) -> Texture2D:
	var portrait: String = breed.get("portrait", "")
	if not portrait.is_empty() and ResourceLoader.exists(portrait):
		return load(portrait)
	var photo: String = breed.get("photo", "")
	if not photo.is_empty() and ResourceLoader.exists(photo):
		return load(photo)
	var sprite: String = breed.get("sprite", "")
	if not sprite.is_empty() and ResourceLoader.exists(sprite):
		return load(sprite)
	return null


func _on_close() -> void:
	_sparks.emitting = false
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, FADE_TIME * 0.7)
	tween.tween_callback(hide)
	if _card_mode:
		_card_mode = false
		return
	# Kolejna rasa z kolejki dopiero po zamknieciu poprzedniej.
	tween.tween_callback(_show_next)
