extends Control
## Okienko "nowa rasa odblokowana". Zlota ramka, obracajace sie promienie,
## iskry i kawalek historii rasy.
##
## Odblokowania potrafia trafic sie po dwa naraz (gracz przekroczyl prog
## pieniedzy i liczbe kur w tej samej klatce), wiec rasy czekaja w kolejce
## i pokazuja sie jedna po drugiej.

const FADE_TIME := 0.32
## Pelny obrot promieni.
const SPIN_SECONDS := 26.0

var _queue: Array[String] = []
var _showing := false

@onready var _rays: TextureRect = $Rays
@onready var _sheet: PanelContainer = $Sheet
@onready var _portrait: TextureRect = $Sheet/Content/Frame/Portrait
@onready var _name: Label = $Sheet/Content/Name
@onready var _rarity: Label = $Sheet/Content/Rarity
@onready var _lore: Label = $Sheet/Content/Lore
@onready var _stats: Label = $Sheet/Content/Stats
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
	frame.set_border_width_all(10)
	frame.border_color = Color("#E8B64C")
	frame.set_content_margin_all(10)
	frame.shadow_color = Color(0.36, 0.25, 0.16, 0.35)
	frame.shadow_size = 10
	$Sheet/Content/Frame.add_theme_stylebox_override("panel", frame)


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
	_fill(GameData.breed(_queue.pop_front()))
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
	_name.text = tr(breed.get("name", ""))
	_rarity.text = tr(breed.get("rarity", "")).to_upper()
	_lore.text = tr(breed.get("lore", ""))
	_stats.text = "%s\n%s" % [
		tr("UNLOCK_PRICE") % NumberFormat.money(float(breed.get("price", 0))),
		tr("UNLOCK_EGG") % [
			NumberFormat.small_money(float(breed.get("egg_value", 0))),
			NumberFormat.duration(float(breed.get("egg_seconds", 0)) / GameData.time_scale())],
	]
	_portrait.texture = _breed_image(breed)


## Zdjecie rasy, a gdy go nie ma — rysunek z wybiegu.
func _breed_image(breed: Dictionary) -> Texture2D:
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
	# Kolejna rasa z kolejki dopiero po zamknieciu poprzedniej.
	tween.tween_callback(_show_next)
