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
	# Zerujemy wysokosc listy z poprzedniego budynku, inaczej jej rozmiar
	# trzymalby panel rozciagniety przy nastepnym otwarciu.
	_scroll.custom_minimum_size.y = 0
	_build_content(building_id)
	_refresh()
	_bottom_spacer.custom_minimum_size.y = SafeArea.bottom_inset(get_viewport())

	_closing = false
	_kill_tween()
	show()
	modulate.a = 0.0
	# Animacja wysuwania ustawia panelowi margines od gory, co zapamietuje jego
	# wysokosc. Przed kolejnym otwarciem trzeba ja uwolnic, inaczej panel
	# zostalby rozciagniety do rozmiaru z poprzedniego budynku.
	_sheet.offset_top = 0.0
	_sheet.offset_bottom = 0.0
	await get_tree().process_frame
	_limit_height()
	await get_tree().process_frame
	# Wysokosc bierzemy z rozmiaru minimalnego, a nie z biezacego: reset_size()
	# sciagnalby tez szerokosc i panel przestalby siegac krawedzi ekranu.
	var shown_y := size.y - _sheet.get_combined_minimum_size().y
	_sheet.position.y = size.y
	_dim.modulate.a = 0.0
	modulate.a = 1.0
	_tween = create_tween().set_parallel()
	_tween.tween_property(_sheet, "position:y", shown_y, SLIDE_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_dim, "modulate:a", 1.0, SLIDE_TIME)


## Panel moze zajac najwyzej polowe ekranu; reszta listy sie przewija.
func _limit_height() -> void:
	_scrollable.reset_size()
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
			_build_coop()
		"incubator":
			_build_incubator()
		"storage":
			_build_storage()
		"shop":
			_build_shop()


func _build_coop() -> void:
	_add_row("PANEL_HENS", func() -> String: return str(Game.state.laying_hen_count()))
	_add_row("PANEL_ROOSTERS", func() -> String: return str(Game.state.rooster_count()))
	_add_row("PANEL_COOP_SPACE",
			func() -> String: return "%d / %d" % [Game.state.coop_occupied(), Game.state.coop_capacity()])
	_add_row("PANEL_FOX_GUARD",
			func() -> String: return tr(_guard_name(Game.state.guard_level)))
	_add_row("PANEL_FARM_CODE", func() -> String: return Cloud.player_id)
	_add_dynamic_row(
			func() -> String: return tr("PANEL_SERVER") if Cloud.is_enabled() else "",
			func() -> String: return tr("PANEL_SERVER_OK") if Cloud.online else tr("PANEL_SERVER_DOWN"))
	_add_row("PANEL_SICK", func() -> String: return str(Game.state.sick_count()))
	_add_row("PANEL_CHICKS", func() -> String: return str(Game.state.chicks.size()))
	_add_row("PANEL_VACCINATED",
			func() -> String: return "%d / %d" % [
				Game.state.hen_count() - Game.state.unvaccinated_count(), Game.state.hen_count()])
	_add_row("PANEL_FEED_LEFT", func() -> String: return _feed_text())
	# Zuzycie podajemy na dzien gospodarstwa, a nie na godzine zegarowa:
	# dzien w grze trwa kilka minut, wiec "kg/godz." brzmialoby absurdalnie.
	_add_row("PANEL_FEED_BURN",
			func() -> String:
				var day := float(GameData.balance().get("day", {}).get("seconds", 600.0))
				return tr("PANEL_FEED_BURN_VALUE") % NumberFormat.amount_only(
					Game.state.feed_per_minute() * day / 60.0))
	_add_row("PANEL_DAYS", func() -> String: return str(Game.state.days))
	_add_progress("PANEL_NEXT_EGG", func() -> float: return _best_progress())

	# Stado wedlug ras, zeby gracz widzial, co wlasciwie ma na wybiegu.
	for breed: Dictionary in GameData.breeds():
		var breed_id: String = breed.get("id", "")
		var breed_name: String = tr(breed.get("name", ""))
		_add_dynamic_row(
				func() -> String: return breed_name if _owned(breed_id) > 0 else "",
				func() -> String:
					# Bez koguta rasa stoi bezproduktywnie — widac to od razu
					# w spisie stada, a nie dopiero po braku jaj w magazynie.
					if not Game.state.has_rooster(breed_id):
						return tr("PANEL_FLOCK_LINE_NO_ROOSTER") % _owned(breed_id)
					return tr("PANEL_FLOCK_LINE") % [
						_owned(breed_id), NumberFormat.money(FarmState.egg_value(breed_id))])

	_add_action(true,
			func() -> bool: return Game.state.money >= float(
					Game.state.next_building_upgrade("coop").get("price", 0)),
			func() -> String:
				var upgrade := Game.state.next_building_upgrade("coop")
				return tr("PANEL_UPGRADE_COOP") % [
					int(upgrade.get("capacity", 0)),
					NumberFormat.money(float(upgrade.get("price", 0)))],
			func() -> void: _on_upgrade("coop"),
			func() -> bool: return not Game.state.next_building_upgrade("coop").is_empty())

	_add_action(false,
			func() -> bool: return Game.state.money >= float(
					Game.state.next_building_upgrade("guard").get("price", 0)),
			func() -> String:
				var upgrade := Game.state.next_building_upgrade("guard")
				return tr("PANEL_UPGRADE_GUARD") % [
					tr(_guard_name(Game.state.guard_level + 1)),
					NumberFormat.money(float(upgrade.get("price", 0))),
					int(round(float(upgrade.get("block_chance", 0.0)) * 100.0))],
			func() -> void: _on_upgrade("guard"),
			func() -> bool: return not Game.state.next_building_upgrade("guard").is_empty())

	var hint := Label.new()
	hint.theme_type_variation = &"NoteLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = tr("PANEL_COOP_HINT")
	_actions.add_child(hint)

	# Kod farmy trzymamy w kurniku, bo to tutaj gracz zaglada najczesciej.
	var note := Label.new()
	note.theme_type_variation = &"NoteLabel"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = tr("PANEL_CLOUD_ON") if Cloud.is_enabled() else tr("PANEL_CLOUD_OFF")
	_actions.add_child(note)
	if Cloud.is_enabled():
		_add_code_entry()


func _build_storage() -> void:
	_add_row("PANEL_EGGS_STORED", func() -> String: return NumberFormat.grouped(Game.state.egg_count()))
	_add_row("PANEL_EGGS_WORTH", func() -> String: return NumberFormat.money(Game.state.eggs_value()))
	_add_row("PANEL_FEED_LEFT", func() -> String: return _feed_text())

	# Jaja z podzialem na rasy — od rasy zalezy cena, wiec warto to widziec.
	for breed: Dictionary in GameData.breeds():
		var breed_id: String = breed.get("id", "")
		var breed_name: String = tr(breed.get("name", ""))
		_add_dynamic_row(
				func() -> String: return breed_name if int(Game.state.eggs.get(breed_id, 0)) > 0 else "",
				func() -> String: return tr("PANEL_EGG_LINE") % [
					int(Game.state.eggs.get(breed_id, 0)),
					NumberFormat.money(int(Game.state.eggs.get(breed_id, 0)) * FarmState.egg_value(breed_id))])

	_add_row("PANEL_FEED_PRICE",
			func() -> String:
				var pack := Game.state.feed_pack()
				return tr("PANEL_FEED_PRICE_VALUE") % [
					int(pack["size"]),
					NumberFormat.money(float(pack["price"]) / maxf(1.0, float(pack["size"])))])
	_add_action(true,
			func() -> bool: return Game.state.money >= float(
					Game.state.next_building_upgrade("storage").get("price", 0)),
			func() -> String:
				var upgrade := Game.state.next_building_upgrade("storage")
				var size := float(upgrade.get("pack_size", 1))
				return tr("PANEL_UPGRADE_STORAGE") % [
					NumberFormat.money(float(upgrade.get("price", 0))),
					int(size),
					NumberFormat.money(float(upgrade.get("pack_price", 0)) / maxf(1.0, size))],
			func() -> void: _on_upgrade("storage"),
			func() -> bool: return not Game.state.next_building_upgrade("storage").is_empty())




## Inkubator: postep wykluwania i wzrostu, wkladanie jaj, rozbudowa.
func _build_incubator() -> void:
	_add_row("PANEL_INCUBATOR_SLOTS",
			func() -> String: return "%d / %d" % [Game.state.incubating.size(), Game.incubator_slots()])
	_add_row("PANEL_EGGS_STORED", func() -> String: return NumberFormat.grouped(Game.state.egg_count()))
	# Pisklę nie wyjdzie z inkubatora, dopoki nie ma dla niego miejsca
	# w kurniku, wiec wolne miejsca licza sie tu razem z tym, co juz w drodze.
	_add_row("PANEL_COOP_LEFT", func() -> String:
		var free := maxi(Game.state.coop_free(), 0)
		if Game.state.coop_reserved() > 0:
			return tr("PANEL_COOP_LEFT_PENDING") % [free, Game.state.coop_reserved()]
		return str(free))

	# Paski postepu: tyle, ile moze miec inkubator po pelnej rozbudowie —
	# nadmiarowe same sie chowaja, wiec panel nie wymaga przebudowy po zakupie.
	for slot in _max_incubator_slots():
		var index := slot
		_add_progress_dynamic(
				func() -> String:
					if index >= Game.state.incubating.size():
						return ""
					var batch: EggBatch = Game.state.incubating[index]
					return tr("PANEL_HATCHING") % tr(GameData.breed(batch.breed_id).get("name", "")),
				func() -> float:
					if index >= Game.state.incubating.size():
						return 0.0
					return (Game.state.incubating[index] as EggBatch).progress())
	for slot in 6:
		var index := slot
		_add_progress_dynamic(
				func() -> String:
					if index >= Game.state.chicks.size():
						return ""
					var chick: Chick = Game.state.chicks[index]
					return tr("PANEL_GROWING") % tr(GameData.breed(chick.breed_id).get("name", "")),
				func() -> float:
					if index >= Game.state.chicks.size():
						return 0.0
					return (Game.state.chicks[index] as Chick).progress())
	_add_dynamic_row(
			func() -> String: return tr("PANEL_CHICKS_MORE") if Game.state.chicks.size() > 6 else "",
			func() -> String: return str(Game.state.chicks.size() - 6))

	var cost := Game.eggs_per_chick()
	for breed: Dictionary in GameData.breeds():
		var breed_id: String = breed.get("id", "")
		var breed_name: String = tr(breed.get("name", ""))
		_add_action(false,
				func() -> bool: return Game.can_incubate(breed_id),
				func() -> String:
					# Wyszarzony przycisk ma powiedziec, czego brakuje: jaj czy
					# miejsca w kurniku. Samo "nie da sie" niczego nie tlumaczy.
					if Game.incubation_blocked_by_coop(breed_id):
						return tr("PANEL_INCUBATE_NO_ROOM") % breed_name
					return tr("PANEL_INCUBATE") % [
						cost, breed_name, int(Game.state.eggs.get(breed_id, 0))],
				func() -> void: _on_incubate(breed_id),
				func() -> bool: return Game.state.owns_breed(breed_id))

	_add_action(true,
			func() -> bool: return Game.state.money >= float(Game.state.next_incubator_upgrade().get("price", 0)),
			func() -> String:
				var upgrade := Game.state.next_incubator_upgrade()
				return tr("PANEL_UPGRADE_INCUBATOR") % [
					int(upgrade.get("slots", 0)), NumberFormat.money(float(upgrade.get("price", 0)))],
			_on_upgrade_incubator,
			func() -> bool: return not Game.state.next_incubator_upgrade().is_empty())

	var hint := Label.new()
	hint.theme_type_variation = &"NoteLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = tr("PANEL_NO_OWN_BREEDS")
	_actions.add_child(hint)
	_refreshers.append(func() -> void: hint.visible = Game.state.hens_by_breed().is_empty())


## Sklep: jaja, pasza, weterynaria i karty ras ze zdjeciem.
func _build_shop() -> void:
	_add_action(true,
			func() -> bool: return Game.state.egg_count() > 0,
			func() -> String: return tr("PANEL_SELL_EGGS") % [
				Game.state.egg_count(), NumberFormat.money(Game.state.eggs_value())],
			_on_sell_eggs)

	_add_action(false,
			func() -> bool: return Game.state.money >= float(Game.state.feed_pack()["price"]),
			func() -> String:
				var pack := Game.state.feed_pack()
				return tr("PANEL_BUY_FEED") % [
					int(pack["size"]), NumberFormat.money(float(pack["price"]))],
			_on_buy_feed)

	# Weterynaria: lek ratuje jedna chora kure, szczepienie chroni cale stado.
	_add_action(false,
			func() -> bool: return Game.state.money >= Game.medicine_price() and Game.state.sick_count() > 0,
			func() -> String: return tr("PANEL_BUY_MEDICINE") % [
				NumberFormat.money(Game.medicine_price()), Game.state.sick_count()],
			_on_buy_medicine,
			func() -> bool: return Game.state.sick_count() > 0)
	_add_action(false,
			func() -> bool: return Game.state.money >= Game.vaccine_price(),
			func() -> String: return tr("PANEL_BUY_VACCINE") % [
				NumberFormat.money(Game.vaccine_price()), Game.state.unvaccinated_count()],
			_on_buy_vaccine,
			func() -> bool: return Game.state.unvaccinated_count() > 0)

	var vaccine_note := Label.new()
	vaccine_note.theme_type_variation = &"NoteLabel"
	vaccine_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vaccine_note.text = tr("PANEL_VACCINE_NOTE")
	_actions.add_child(vaccine_note)

	for breed: Dictionary in GameData.breeds():
		_add_breed_card(breed)


## Najwieksza liczba miejsc, jaka inkubator moze miec po rozbudowie.
func _max_incubator_slots() -> int:
	var incubator: Dictionary = GameData.balance().get("incubator", {})
	var upgrades: Array = incubator.get("upgrades", [])
	if upgrades.is_empty():
		return int(incubator.get("slots", 3))
	return int(Dictionary(upgrades[-1]).get("slots", incubator.get("slots", 3)))


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


## Wiersz, ktory chowa sie, gdy `label_provider` zwroci pusty napis.
func _add_dynamic_row(label_provider: Callable, value_provider: Callable) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.theme_type_variation = &"NoteLabel"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value := Label.new()
	value.theme_type_variation = &"NoteLabel"
	row.add_child(label)
	row.add_child(value)
	_rows.add_child(row)
	_refreshers.append(func() -> void:
		var text: String = label_provider.call()
		row.visible = text != ""
		if not row.visible:
			return
		label.text = text
		value.text = value_provider.call())


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
	var sold := Game.state.egg_count()
	var earned := Game.sell_eggs()
	if earned > 0.0:
		_flash(tr("PANEL_SOLD") % [sold, NumberFormat.money(earned)])


func _on_buy_feed() -> void:
	if Game.buy_feed():
		_flash(tr("PANEL_FEED_BOUGHT"))


func _on_buy_hen(breed_id: String, breed_name: String, rooster: bool = false) -> void:
	if Game.buy_hen(breed_id, rooster):
		var key := "PANEL_ROOSTER_BOUGHT" if rooster else "PANEL_HEN_BOUGHT"
		_flash(tr(key) % breed_name)


## Ubija chora sztuke. Najpierw kury, a koguta dopiero wtedy, gdy to on jest
## chory — inaczej jedno nieuwazne stukniecie zostawialoby rase bez koguta.
func _on_cull_hen(breed_id: String, breed_name: String) -> void:
	var rooster := not Game.has_sick(breed_id)
	if Game.cull_hen(breed_id, rooster):
		_flash(tr("PANEL_HEN_CULLED") % breed_name)


func _on_sell_hen(breed_id: String, breed_name: String, rooster: bool = false) -> void:
	var earned := Game.sell_hen(breed_id, rooster)
	if earned > 0.0:
		var key := "PANEL_ROOSTER_SOLD" if rooster else "PANEL_HEN_SOLD"
		_flash(tr(key) % [breed_name, NumberFormat.money(earned)])


func _on_buy_medicine() -> void:
	if not Game.buy_medicine():
		_flash(tr("PANEL_NO_MONEY"))


func _on_buy_vaccine() -> void:
	if not Game.buy_vaccine():
		_flash(tr("PANEL_NO_MONEY"))


func _on_upgrade_incubator() -> void:
	if not Game.upgrade_incubator():
		_flash(tr("PANEL_NO_MONEY"))


func _on_upgrade(building_id: String) -> void:
	if not Game.upgrade_building(building_id):
		_flash(tr("PANEL_NO_MONEY"))


## Pole do przepisania kodu farmy z innego urzadzenia. To jedyna droga
## powrotu do swojej gry po wyczyszczeniu danych przegladarki, wiec siedzi
## w magazynie, tuz pod kodem wlasnej farmy.
func _add_code_entry() -> void:
	var hint := Label.new()
	hint.theme_type_variation = &"NoteLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = tr("PANEL_CODE_HINT")
	_actions.add_child(hint)

	var field := LineEdit.new()
	field.placeholder_text = tr("PANEL_CODE_PLACEHOLDER")
	field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	field.max_length = 6
	# Na telefonie wyskakuje klawiatura numeryczna, a nie pelna.
	field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_actions.add_child(field)

	var button := Button.new()
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.text = tr("PANEL_CODE_LOAD")
	button.pressed.connect(func() -> void:
		if Game.restore_from_code(field.text):
			field.text = "")
	_actions.add_child(button)
	# Enter na klawiaturze telefonu robi to samo co przycisk.
	field.text_submitted.connect(func(_text: String) -> void: button.emit_signal("pressed"))


## Nazwa obrony przed lisem na danym poziomie: nic, plot albo pies.
func _guard_name(level: int) -> String:
	match level:
		1:
			return "PANEL_FOX_GUARD_FENCE"
		2:
			return "PANEL_FOX_GUARD_DOG"
		3:
			return "PANEL_FOX_GUARD_PACK"
	return "PANEL_FOX_GUARD_NONE"


## Ile kur danej rasy ma gracz.
func _owned(breed_id: String) -> int:
	return int(Game.state.hens_by_breed().get(breed_id, 0))


## Pasek postepu, ktory sam sie chowa, gdy nie ma czego pokazywac.
func _add_progress_dynamic(label_provider: Callable, value_provider: Callable) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.theme_type_variation = &"NoteLabel"
	var bar := ProgressBar.new()
	bar.max_value = 1.0
	bar.step = 0.001
	bar.show_percentage = false
	bar.custom_minimum_size.y = 30
	box.add_child(label)
	box.add_child(bar)
	_rows.add_child(box)
	_refreshers.append(func() -> void:
		var text: String = label_provider.call()
		box.visible = text != ""
		if not box.visible:
			return
		label.text = text
		bar.value = value_provider.call())


## Karta rasy w sklepie: zdjecie (albo rysunek), nazwa, rzadkosc i przycisk.
## Zdjecia realnych kur wrzuca sie do assets/photos/<id>.jpg — jesli pliku
## nie ma, karta pokazuje rysunek z wybiegu, wiec sklep dziala od razu.
func _add_breed_card(breed: Dictionary) -> void:
	var breed_id: String = breed.get("id", "")
	var breed_name: String = tr(breed.get("name", ""))
	var price := float(breed.get("price", 0))

	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 10)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 20)

	var picture := TextureRect.new()
	picture.custom_minimum_size = Vector2(210, 210)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.texture = _breed_image(breed)
	# Zdjecia realnych kur sa prostokatne — obcinamy je do kwadratu karty.
	picture.clip_contents = true
	top.add_child(picture)

	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 4)
	var title := Label.new()
	title.text = breed_name
	var subtitle := Label.new()
	subtitle.theme_type_variation = &"NoteLabel"
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var numbers := Label.new()
	numbers.theme_type_variation = &"NoteLabel"
	numbers.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	texts.add_child(title)
	texts.add_child(subtitle)
	texts.add_child(numbers)
	top.add_child(texts)
	card.add_child(top)

	# Ostrzezenie widoczne tylko wtedy, gdy kury tej rasy stoja bez koguta
	# i przez to nie znosza ani jednego jajka.
	var no_rooster := Label.new()
	no_rooster.theme_type_variation = &"NoteLabel"
	no_rooster.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	no_rooster.text = tr("PANEL_NO_ROOSTER")
	card.add_child(no_rooster)

	var buy := Button.new()
	buy.theme_type_variation = &"PrimaryButton"
	buy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	buy.pressed.connect(func() -> void: _on_buy_hen(breed_id, breed_name))
	card.add_child(buy)

	var buy_rooster := Button.new()
	buy_rooster.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	buy_rooster.pressed.connect(func() -> void: _on_buy_hen(breed_id, breed_name, true))
	card.add_child(buy_rooster)

	var sell := Button.new()
	sell.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sell.pressed.connect(func() -> void: _on_sell_hen(breed_id, breed_name))
	card.add_child(sell)

	var sell_rooster := Button.new()
	sell_rooster.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sell_rooster.pressed.connect(func() -> void: _on_sell_hen(breed_id, breed_name, true))
	card.add_child(sell_rooster)

	# Chorej sztuki skup nie przyjmuje. Jedyne, co mozna z nia zrobic bez
	# pieniedzy na lek, to ubic — za darmo, zeby zwolnic miejsce w kurniku.
	var cull := Button.new()
	cull.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cull.pressed.connect(func() -> void: _on_cull_hen(breed_id, breed_name))
	card.add_child(cull)

	_actions.add_child(card)

	_refreshers.append(func() -> void:
		var owned := _owned(breed_id)
		var cocks := Game.state.hens_of_breed(breed_id, false, true)
		var poor := Game.state.money < price
		buy.text = tr("PANEL_BUY_HEN") % NumberFormat.money(price)
		buy.disabled = poor
		buy_rooster.text = tr("PANEL_BUY_ROOSTER") % [NumberFormat.money(price), cocks]
		buy_rooster.disabled = poor
		no_rooster.visible = owned > 0 and cocks == 0
		# Skup bierze tylko zdrowe sztuki, wiec licznik na przycisku sprzedazy
		# pokazuje zdrowe, a nie cale stado tej rasy.
		var healthy := Game.state.hens_of_breed(breed_id, true)
		var healthy_cocks := Game.state.hens_of_breed(breed_id, true, true)
		sell.visible = healthy > 0
		sell.text = tr("PANEL_SELL_HEN") % [
			NumberFormat.money(FarmState.hen_sell_price(breed_id)), healthy]
		sell_rooster.visible = healthy_cocks > 0
		sell_rooster.text = tr("PANEL_SELL_ROOSTER") % [
			NumberFormat.money(FarmState.hen_sell_price(breed_id)), healthy_cocks]
		var sick := owned - healthy + cocks - healthy_cocks
		cull.visible = sick > 0
		cull.text = tr("PANEL_CULL_HEN") % sick
		subtitle.text = "%s · %s" % [tr(breed.get("rarity", "")), tr(breed.get("desc", ""))]
		numbers.text = tr("PANEL_BREED_NUMBERS") % [
			NumberFormat.money(FarmState.egg_value(breed_id)),
			int(float(breed.get("egg_seconds", 0))),
			owned])


## Grafika rasy: najpierw prawdziwe zdjecie, w razie jego braku rysunek.
func _breed_image(breed: Dictionary) -> Texture2D:
	var photo: String = breed.get("photo", "")
	if photo != "" and ResourceLoader.exists(photo):
		return load(photo) as Texture2D
	return load(breed.get("sprite", "")) as Texture2D


## Czego brakuje do odblokowania rasy, po przecinku.

func _on_incubate(breed_id: String) -> void:
	if Game.incubate(breed_id):
		_flash(tr("PANEL_EGGS_IN"))

