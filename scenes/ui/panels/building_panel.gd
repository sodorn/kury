extends Control
## Dolny panel budynku: opis, stan i akcje (sprzedaz, zakupy).
##
## Zawartosc zalezy od budynku i powstaje w kodzie, bo liczba przyciskow
## zmienia sie wraz z liczba ras. Panel tylko czyta Game.state i wola metody
## Game — nie liczy niczego sam.

const SLIDE_TIME := 0.22
## Jak dlugo widac komunikat w rodzaju "Sprzedano 12 jaj".
const FLASH_SECONDS := 2.5
## Co ile sekund odswiezac pola przy otwartym panelu (pasek postepu plynie).
const REFRESH_SECONDS := 0.2

var _tween: Tween
var _closing := false
var _building_id := ""
var _flash_left := 0.0
var _refresh_left := 0.0
## Odswiezacze pol, ktore zaleza od stanu gry; wolane po kazdej zmianie zasobow.
var _refreshers: Array[Callable] = []

@onready var _dim: ColorRect = $Dim
@onready var _sheet: PanelContainer = $Sheet
@onready var _title: Label = $Sheet/Content/Header/Title
@onready var _close: TextureButton = $Sheet/Content/Header/Close
@onready var _picture: TextureRect = $Sheet/Content/Body/Picture
@onready var _description: Label = $Sheet/Content/Body/Text/Description
@onready var _status: Label = $Sheet/Content/Body/Text/Status
@onready var _scroll: ScrollContainer = $Sheet/Content/Scroll
@onready var _scrollable: VBoxContainer = $Sheet/Content/Scroll/Scrollable
@onready var _rows: VBoxContainer = $Sheet/Content/Scroll/Scrollable/Rows
@onready var _actions: VBoxContainer = $Sheet/Content/Scroll/Scrollable/Actions
@onready var _bottom_spacer: Control = $Sheet/Content/BottomSpacer


func _ready() -> void:
	hide()
	_dim.gui_input.connect(_on_dim_input)
	_close.pressed.connect(close)
	Events.building_tapped.connect(open)
	Events.resources_changed.connect(_refresh)


func _process(delta: float) -> void:
	if visible:
		_refresh_left -= delta
		if _refresh_left <= 0.0:
			_refresh_left = REFRESH_SECONDS
			_refresh()
	if _flash_left <= 0.0:
		return
	_flash_left -= delta
	if _flash_left <= 0.0:
		_status.text = ""


func is_open() -> bool:
	return visible and not _closing


func open(building_id: String, picture: Texture2D = null) -> void:
	var def := GameData.building(building_id)
	if def.is_empty():
		return
	_building_id = building_id
	_title.text = tr(def.get("name", ""))
	_description.text = tr(def.get("desc", ""))
	_picture.texture = picture
	_status.text = ""
	_flash_left = 0.0
	_build_content(building_id)
	_refresh()
	_bottom_spacer.custom_minimum_size.y = SafeArea.bottom_inset(get_viewport())

	_closing = false
	_kill_tween()
	show()
	modulate.a = 0.0
	# Jedna klatka, zeby kontenery policzyly wysokosc panelu przed animacja.
	await get_tree().process_frame
	_limit_height()
	await get_tree().process_frame
	var shown_y := size.y - _sheet.size.y
	_sheet.position.y = size.y
	_dim.modulate.a = 0.0
	modulate.a = 1.0
	_tween = create_tween().set_parallel()
	_tween.tween_property(_sheet, "position:y", shown_y, SLIDE_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_dim, "modulate:a", 1.0, SLIDE_TIME)


## Panel moze zajac najwyzej polowe ekranu; reszta listy sie przewija.
func _limit_height() -> void:
	var wanted := _scrollable.get_combined_minimum_size().y
	_scroll.custom_minimum_size.y = minf(wanted, size.y * 0.5)


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


# --- zawartosc zalezna od budynku ---------------------------------------


func _build_content(building_id: String) -> void:
	_refreshers.clear()
	for container in [_rows, _actions]:
		for child in container.get_children():
			child.queue_free()
			container.remove_child(child)

	match building_id:
		"coop":
			_add_row("PANEL_HENS", func() -> String: return str(Game.state.hen_count()))
			_add_row("PANEL_FEED_LEFT", func() -> String: return _feed_text())
			_add_progress("PANEL_NEXT_EGG", func() -> float: return _best_progress())
			for breed: Dictionary in GameData.breeds():
				var owned_id: String = breed.get("id", "")
				var owned_name: String = tr(breed.get("name", ""))
				var sell_price := FarmState.hen_sell_price(owned_id)
				_add_action(false,
						func() -> bool: return _owned(owned_id) > 0,
						func() -> String: return tr("PANEL_SELL_HEN") % [owned_name, _owned(owned_id), sell_price],
						func() -> void: _on_sell_hen(owned_id, owned_name),
						func() -> bool: return _owned(owned_id) > 0)
		"storage":
			_add_row("PANEL_EGGS_STORED", func() -> String: return NumberFormat.grouped(Game.state.eggs))
			_add_row("PANEL_EGGS_WORTH", func() -> String: return NumberFormat.grouped(Game.state.eggs_value()))
			_add_row("PANEL_FEED_LEFT", func() -> String: return _feed_text())
		"shop":
			_add_action(true,
					func() -> bool: return Game.state.eggs > 0,
					func() -> String: return tr("PANEL_SELL_EGGS") % [Game.state.eggs, Game.state.eggs_value()],
					_on_sell_eggs)
			var economy: Dictionary = GameData.balance().get("economy", {})
			var pack := int(economy.get("feed_pack_size", 0))
			var pack_price := int(economy.get("feed_pack_price", 0))
			_add_action(false,
					func() -> bool: return Game.state.money >= pack_price,
					func() -> String: return tr("PANEL_BUY_FEED") % [pack, pack_price],
					_on_buy_feed)
			for breed: Dictionary in GameData.breeds():
				var breed_id: String = breed.get("id", "")
				var price := int(breed.get("price", 0))
				var breed_name: String = tr(breed.get("name", ""))
				var rarity: String = tr(breed.get("rarity", ""))
				_add_action(false,
						func() -> bool: return Game.state.money >= price,
						func() -> String: return tr("PANEL_BUY_HEN") % [breed_name, rarity, price],
						func() -> void: _on_buy_hen(breed_id, breed_name))
		"incubator":
			_add_row("PANEL_EGGS_STORED", func() -> String: return NumberFormat.grouped(Game.state.eggs))


func _add_row(label_key: String, value_provider: Callable) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = tr(label_key)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value := Label.new()
	value.theme_type_variation = &"CounterLabel"
	row.add_child(label)
	row.add_child(value)
	_rows.add_child(row)
	_refreshers.append(func() -> void: value.text = value_provider.call())


func _add_progress(label_key: String, value_provider: Callable) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = tr(label_key)
	label.theme_type_variation = &"NoteLabel"
	var bar := ProgressBar.new()
	bar.max_value = 1.0
	bar.step = 0.001
	bar.show_percentage = false
	bar.custom_minimum_size.y = 34
	box.add_child(label)
	box.add_child(bar)
	_rows.add_child(box)
	_refreshers.append(func() -> void: bar.value = value_provider.call())


## `visible_provider` pozwala ukryc przycisk zupelnie (np. sprzedaz rasy,
## ktorej gracz nie ma) zamiast pokazywac go wyszarzonego.
func _add_action(primary: bool, enabled_provider: Callable, text_provider: Callable,
		on_pressed: Callable, visible_provider: Callable = Callable()) -> void:
	var button := Button.new()
	if primary:
		button.theme_type_variation = &"PrimaryButton"
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.pressed.connect(on_pressed)
	_actions.add_child(button)
	_refreshers.append(func() -> void:
		if visible_provider.is_valid():
			button.visible = visible_provider.call()
			if not button.visible:
				return
		button.text = text_provider.call()
		button.disabled = not enabled_provider.call())


func _refresh() -> void:
	if Game.state == null:
		return
	for refresher in _refreshers:
		refresher.call()


func _feed_text() -> String:
	return NumberFormat.grouped(int(floor(Game.state.feed)))


## Postep kury, ktorej najblizej do zniesienia jaja.
func _best_progress() -> float:
	var best := 0.0
	for hen: Chicken in Game.state.chickens:
		best = maxf(best, hen.progress())
	return best


func _flash(message: String) -> void:
	_status.text = message
	_flash_left = FLASH_SECONDS


func _on_sell_eggs() -> void:
	var sold := Game.state.eggs
	var earned := Game.sell_eggs()
	if earned > 0:
		_flash(tr("PANEL_SOLD") % [sold, earned])


func _on_buy_feed() -> void:
	if Game.buy_feed():
		_flash(tr("PANEL_FEED_BOUGHT"))


func _on_buy_hen(breed_id: String, breed_name: String) -> void:
	if Game.buy_hen(breed_id):
		_flash(tr("PANEL_HEN_BOUGHT") % breed_name)


func _on_sell_hen(breed_id: String, breed_name: String) -> void:
	var earned := Game.sell_hen(breed_id)
	if earned > 0:
		_flash(tr("PANEL_HEN_SOLD") % [breed_name, earned])


## Ile kur danej rasy ma gracz.
func _owned(breed_id: String) -> int:
	return int(Game.state.hens_by_breed().get(breed_id, 0))
