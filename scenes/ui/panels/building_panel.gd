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
## Otwarte pytanie "na pewno?", zeby nie dalo sie otworzyc dwoch naraz.
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
@onready var _scrollable: VBoxContainer = $Sheet/Content/Scroll/Gutter/Scrollable
@onready var _rows: VBoxContainer = $Sheet/Content/Scroll/Gutter/Scrollable/Rows
@onready var _actions: VBoxContainer = $Sheet/Content/Scroll/Gutter/Scrollable/Actions
## Rozbudowa stoi NA GORZE listy, nad informacjami (wlasciciel, 25.11).
@onready var _upgrades: VBoxContainer = $Sheet/Content/Scroll/Gutter/Scrollable/Upgrades
## Paski postepu stoja POD przyciskami: wlasciciel chcial miec przyciski
## pod palcem u gory, a odliczanie na dole.
@onready var _bars: VBoxContainer = $Sheet/Content/Scroll/Gutter/Scrollable/Bars
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
	# Szerokosc tez wracamy do ekranu: panel raz rozepchniety zostawal szeroki.
	_sheet.offset_left = 0.0
	_sheet.offset_right = 0.0
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
	for container in [_upgrades, _rows, _actions, _bars]:
		for child in container.get_children():
			child.queue_free()
			container.remove_child(child)

	if Game.is_admin() and building_id != "shop":
		_add_admin_levels(building_id)
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
	_add_upgrade("coop", func(upgrade: Dictionary) -> String:
			return tr("UPG_COOP_EFFECT") % NumberFormat.count(int(upgrade.get("capacity", 0)),
					"miejsce", "miejsca", "miejsc"))
	_add_purchase("dog", "PANEL_BUY_DOG", func(upgrade: Dictionary) -> String:
			var text := tr("PANEL_DOG_NEXT") % [String(upgrade.get("name", "")),
					NumberFormat.amount_only(float(upgrade.get("interval", 0))),
					int(round(float(upgrade.get("chance", 0.0)) * 100.0))]
			var kill := int(round(float(upgrade.get("kill_chance", 0.0)) * 100.0))
			if kill > 0:
				text += tr("PANEL_DOG_NEXT_KILL") % kill
			var deaf := int(round(float(upgrade.get("deaf_chance", 0.0)) * 100.0))
			if deaf > 0:
				text += tr("PANEL_DOG_NEXT_DEAF") % deaf
			var quit := int(round(float(upgrade.get("quit_chance", 0.0)) * 100.0))
			if quit > 0:
				text += tr("PANEL_DOG_NEXT_QUIT") % [quit,
						NumberFormat.amount_only(float(upgrade.get("quit_after", 0)))]
			return text)
	_add_purchase("guard", "PANEL_BUY_GUARD", func(upgrade: Dictionary) -> String:
			return tr("PANEL_GUARD_NEXT") % [String(upgrade.get("name", "")),
					int(round(float(upgrade.get("block_chance", 0.0)) * 100.0))])

	_add_level_row(func() -> int: return Game.state.coop_level, _building_levels("coop"),
			func() -> String: return _level_name("coop"))
	_add_row("PANEL_HENS", func() -> String: return str(Game.state.laying_hen_count()))
	_add_row("PANEL_ROOSTERS", func() -> String: return str(Game.state.rooster_count()))
	# Jaja w inkubatorze i pisklęta rezerwuja miejsca w kurniku, wiec musza byc
	# widoczne obok zajetych — inaczej "30/60" wyglada, jakby bylo pelno luzu.
	_add_row("PANEL_COOP_PENDING", func() -> String: return str(Game.state.coop_reserved()))
	_add_row("PANEL_COOP_SPACE",
			func() -> String: return "%d / %d" % [Game.state.coop_occupied(), Game.state.coop_capacity()])
	_add_row("PANEL_FOX_FENCE",
			func() -> String:
				if Game.state.guard_level <= 0:
					return tr("PANEL_FOX_GUARD_NONE")
				return "%s — %d%%" % [_owned_name("guard", Game.state.guard_level),
						int(round(Game.state.fox_block_chance() * 100.0))])
	_add_row("PANEL_FOX_DOG",
			func() -> String:
				if Game.state.dog_level <= 0:
					return tr("PANEL_DOG_NONE")
				return _owned_name("dog", Game.state.dog_level))
	_add_row("PANEL_FARM_CODE", func() -> String: return Cloud.player_id)
	_add_dynamic_row(
			func() -> String: return tr("PANEL_SERVER") if Cloud.is_enabled() else "",
			func() -> String: return tr("PANEL_SERVER_OK") if Cloud.online else tr("PANEL_SERVER_DOWN"))
	_add_row("PANEL_SICK", func() -> String: return str(Game.state.sick_count()))
	_add_row("PANEL_DISEASE", func() -> String: return _disease_text())
	_add_row("PANEL_CHICKS", func() -> String: return str(Game.state.chicks.size()))
	_add_row("PANEL_VACCINATED",
			func() -> String: return "%d / %d" % [
				Game.state.vaccinated_count(), Game.state.hen_count()])
	_add_row("PANEL_FEED_LEFT", func() -> String: return _feed_text())
	_add_feed_time_rows()
	# Wiek farmy w czasie ZIEMSKIM. Do 12.18 byl tu "dzien gospodarstwa"
	# (pol godziny zegara) - wlasciciel nie wiedzial, czy to jego doby.
	_add_row("PANEL_FARM_AGE", func() -> String: return NumberFormat.duration(_farm_age()))
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
						_owned(breed_id), NumberFormat.small_money(FarmState.egg_value(breed_id))])

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
	_add_upgrade("storage", func(upgrade: Dictionary) -> String:
			return tr("UPG_STORAGE_EFFECT") % NumberFormat.eggs(int(upgrade.get("egg_capacity", 0))))
	_add_level_row(func() -> int: return Game.state.storage_level, _building_levels("storage"),
			func() -> String: return _level_name("storage"))
	_add_row("PANEL_EGGS_STORED", func() -> String: return "%s / %s" % [
			NumberFormat.grouped(Game.state.egg_count()),
			NumberFormat.grouped(Game.state.egg_capacity())])
	_add_row("PANEL_EGGS_WORTH", func() -> String: return NumberFormat.money(Game.state.eggs_value()))
	_add_row("PANEL_FEED_LEFT", func() -> String: return _feed_text())
	_add_feed_time_rows()

	# Jaja z podzialem na rasy — od rasy zalezy cena, wiec warto to widziec.
	for breed: Dictionary in GameData.breeds():
		var breed_id: String = breed.get("id", "")
		var breed_name: String = tr(breed.get("name", ""))
		_add_dynamic_row(
				func() -> String: return breed_name if int(Game.state.eggs.get(breed_id, 0)) > 0 else "",
				func() -> String: return tr("PANEL_EGG_LINE") % [
					int(Game.state.eggs.get(breed_id, 0)),
					NumberFormat.money(int(Game.state.eggs.get(breed_id, 0)) * FarmState.egg_value(breed_id))])


## Inkubator: postep wykluwania i wzrostu, wkladanie jaj, rozbudowa.
func _build_incubator() -> void:
	var incubator: Dictionary = GameData.balance().get("incubator", {})
	var levels: int = (incubator.get("upgrades", []) as Array).size() + 1
	_add_upgrade("incubator", func(upgrade: Dictionary) -> String:
			var slots := int(upgrade.get("slots", 0))
			var eggs := int(upgrade.get("eggs", slots * Game.eggs_per_chick()))
			return tr("UPG_INCUBATOR_EFFECT") % [NumberFormat.eggs(eggs),
				NumberFormat.count(slots, "pisklę", "pisklęta", "piskląt")])
	_add_level_row(func() -> int: return Game.state.incubator_level, levels,
			func() -> String: return _level_name("incubator"))
	_add_row("PANEL_INCUBATOR_SLOTS",
			func() -> String: return "%d / %d" % [Game.state.incubating.size(), Game.incubator_slots()])
	_add_row("PANEL_EGGS_STORED", func() -> String: return "%s / %s" % [
			NumberFormat.grouped(Game.state.egg_count()),
			NumberFormat.grouped(Game.state.egg_capacity())])
	# Pisklę nie wyjdzie z inkubatora, dopoki nie ma dla niego miejsca
	# w kurniku, wiec wolne miejsca licza sie tu razem z tym, co juz w drodze.
	_add_row("PANEL_COOP_LEFT", func() -> String:
		var free := maxi(Game.state.coop_free(), 0)
		if Game.state.coop_reserved() > 0:
			return tr("PANEL_COOP_LEFT_PENDING") % [free, Game.state.coop_reserved()]
		return str(free))

	# Pusty inkubator mowil dotad tylko tyle, ze nic sie nie dzieje. Teraz
	# pisze, co z tym zrobic.
	var empty_note := Label.new()
	empty_note.theme_type_variation = &"NoteLabel"
	empty_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	empty_note.text = tr("PANEL_INCUBATOR_EMPTY")
	_bars.add_child(empty_note)
	_refreshers.append(func() -> void:
		empty_note.visible = Game.state.incubating.is_empty() and Game.state.chicks.is_empty())

	# Paski postepu: tyle, ile moze miec inkubator po pelnej rozbudowie —
	# nadmiarowe same sie chowaja, wiec panel nie wymaga przebudowy po zakupie.
	_add_group("PANEL_INCUBATOR_GROUP", func() -> bool: return not Game.state.incubating.is_empty())
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
					return (Game.state.incubating[index] as EggBatch).progress(),
				func() -> String:
					if index >= Game.state.incubating.size():
						return ""
					var batch: EggBatch = Game.state.incubating[index]
					return "%d%% · %s" % [int(batch.progress() * 100.0),
							_countdown(batch.total_seconds() - batch.elapsed)])

	_add_group("PANEL_CHICKS_GROUP", func() -> bool: return not Game.state.chicks.is_empty())
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
					return (Game.state.chicks[index] as Chick).progress(),
				func() -> String:
					if index >= Game.state.chicks.size():
						return ""
					var chick: Chick = Game.state.chicks[index]
					return "%d%% · %s" % [int(chick.progress() * 100.0),
							_countdown(chick.total_seconds() - chick.grown)])
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
					if Game.state.is_building("incubator"):
						return tr("PANEL_INCUBATE_BUILDING")
					if Game.incubation_blocked_by_coop(breed_id):
						return tr("PANEL_INCUBATE_NO_ROOM") % [
							breed_name, Game.state.coop_occupied(), Game.state.coop_reserved()]
					return tr("PANEL_INCUBATE") % [
						cost, breed_name, int(Game.state.eggs.get(breed_id, 0))],
				func() -> void: _on_incubate(breed_id),
				# Wiersz widac, gdy gracz ma kury tej rasy ALBO same jaja. Po
				# sprzedaniu calego stada jaja zostaja w magazynie i nadal
				# wolno je wylec — przycisk nie moze wtedy znikac.
				func() -> bool: return _owned(breed_id) > 0 \
						or int(Game.state.eggs.get(breed_id, 0)) > 0)


	# Padlo pytanie, czy rozbudowa przyspiesza wykluwanie. Nie — i teraz
	# panel mowi to wprost, zanim ktos wyda 20 000 zl na zly domysl.
	var speed_note := Label.new()
	speed_note.theme_type_variation = &"NoteLabel"
	speed_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	speed_note.text = tr("PANEL_INCUBATOR_SPEED")
	_actions.add_child(speed_note)

	var hint := Label.new()
	hint.theme_type_variation = &"NoteLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = tr("PANEL_NO_OWN_BREEDS")
	_actions.add_child(hint)
	_refreshers.append(func() -> void: hint.visible = Game.state.hens_by_breed().is_empty())


## Sklep: jaja, pasza, weterynaria i karty ras ze zdjeciem.
func _build_shop() -> void:
	# Jaja idą partiami (economy.egg_sale_lot), najstarsze najpierw. Gdy
	# zostalo mniej niz partia, przycisk sprzedaje resztke - inaczej zgnilaby.
	_add_action(true,
			func() -> bool: return Game.state.egg_count() > 0,
			func() -> String:
				var n := mini(Game.egg_sale_lot(), Game.state.egg_count())
				var lot := Game.state.oldest_eggs(n)
				return tr("PANEL_SELL_EGGS") % [
					NumberFormat.eggs(n), NumberFormat.money(FarmState.eggs_worth(lot))],
			_on_sell_eggs)
	# 13.0 (wlasciciel 26.11): drugi przycisk - sprzedaj 80% jaj z magazynu.
	var sell_most := _grid_button(&"SellButton")
	sell_most.name = "SellEggsMost"
	sell_most.pressed.connect(_on_sell_eggs_share)
	_actions.add_child(sell_most)
	_refreshers.append(func() -> void:
		var n := _eggs_share_count()
		sell_most.disabled = n <= 0
		sell_most.text = tr("PANEL_SELL_EGGS_SHARE") % [NumberFormat.eggs(n),
				NumberFormat.money(FarmState.eggs_worth(Game.state.oldest_eggs(n)))])

	# Pasza (wlasciciel 25.11): dwa zwykle przyciski obok siebie - worek
	# i big-bag z data/rozbudowy.json. Cena za kg spada z poziomem magazynu.
	var feed_row := HBoxContainer.new()
	feed_row.name = "FeedRow"
	feed_row.add_theme_constant_override("separation", 12)
	_actions.add_child(feed_row)
	for option in FarmState.feed_option_count():
		var feed_button := _grid_button(&"")
		feed_button.name = "Feed%d" % option
		feed_button.pressed.connect(func() -> void: _on_buy_feed(option))
		feed_row.add_child(feed_button)
		_refreshers.append(func() -> void:
			var pack := Game.state.feed_pack(option)
			# small_money: przy tanszym magazynie worek kosztuje np. 34,40 zl,
			# a money() pokazaloby 34 zl i klamalo o pobrana kwote.
			var text := tr("PANEL_BUY_FEED") % [
				NumberFormat.feed_unit(pack), NumberFormat.small_money(float(pack["price"]))]
			text = text.left(1).to_upper() + text.substr(1)
			feed_button.disabled = Game.state.money < float(pack["price"])
			feed_button.text = text)

	# Weterynaria: leku nie ma (12.20) — szczepienie chroni zdrowe stado.
	# Od 12.25 zwykly przycisk, bez suwaka (wlasciciel 25.11).
	var vaccine := _grid_button(&"")
	vaccine.name = "Vaccine"
	vaccine.pressed.connect(_on_buy_vaccine)
	_actions.add_child(vaccine)
	_refreshers.append(func() -> void:
		vaccine.visible = Game.state.unvaccinated_count() > 0
		vaccine.disabled = Game.state.money < Game.vaccine_price()
		vaccine.text = tr("PANEL_BUY_VACCINE") % [
			NumberFormat.money(Game.vaccine_price()), Game.state.unvaccinated_count()])

	var vaccine_note := Label.new()
	vaccine_note.theme_type_variation = &"NoteLabel"
	vaccine_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vaccine_note.text = tr("PANEL_VACCINE_NOTE")
	_actions.add_child(vaccine_note)

	for breed: Dictionary in GameData.breeds():
		_add_breed_card(breed)


## Stan choroby w jednej linijce: ognisko w toku albo ryzyko wybuchu przy
## obecnym stadzie. Przerwa po ognisku (disease_calm) dziala, ale gracz jej
## nie widzi - choroba ma byc losowa, nie zapowiedziana (wlasciciel 26.11).
func _disease_text() -> String:
	var state := Game.state
	if state.outbreak_on:
		var rasa := tr(String(GameData.breed(state.outbreak_breed).get("name", "")))
		if state.outbreak_left > 0:
			return tr("PANEL_DISEASE_ON") % [rasa, state.outbreak_left, state.sick_count()]
		return tr("PANEL_DISEASE_ON_DONE") % state.sick_count()
	var rate := FarmState.disease_rate_per_hour(state.chickens.size())
	var level := 0
	if rate > 0.0:
		level = 1
	if rate >= 0.15:
		level = 2
	if rate >= 0.4:
		level = 3
	if rate >= 1.0:
		level = 4
	return tr("PANEL_DISEASE_RISK") % tr("DISEASE_RISK_%d" % level)


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
	_row_value(value)
	row.add_child(label)
	row.add_child(value)
	_rows.add_child(row)
	_refreshers.append(func() -> void: value.text = value_provider.call())


## Wartosc w wierszu panelu: zawija sie i przylega do prawej. Bez tego dluga
## nazwa poziomu ("ekologiczna ferma: kurnik 12x20 m...") rozpychala panel
## szerzej niz ekran, a ten zostawal szeroki tez w innych budynkach -
## wlasciciel widzial tekst uciety na krawedziach (zgloszenie 25.11).
func _row_value(value: Label) -> void:
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.size_flags_stretch_ratio = 1.6
	value.custom_minimum_size.x = 10.0


## Wiersz, ktory chowa sie, gdy `label_provider` zwroci pusty napis.
func _add_dynamic_row(label_provider: Callable, value_provider: Callable) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.theme_type_variation = &"NoteLabel"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value := Label.new()
	value.theme_type_variation = &"NoteLabel"
	_row_value(value)
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
	_bars.add_child(box)
	_refreshers.append(func() -> void: bar.value = value_provider.call())


## `visible_provider` pozwala ukryc przycisk zupelnie (np. sprzedaz rasy,
## ktorej gracz nie ma) zamiast pokazywac go wyszarzonego.
## `slide` = przycisk-suwak: akcja rusza dopiero po przeciagnieciu palcem
## od lewej do prawej. Tak sa zrobione wszystkie transakcje, ktore kiedys
## pytaly "na pewno?", i cala rozbudowa (wlasciciel, 25.11).
func _add_action(primary: bool, enabled_provider: Callable, text_provider: Callable,
		on_pressed: Callable, visible_provider: Callable = Callable(),
		price_provider: Callable = Callable(), container: VBoxContainer = null,
		slide: bool = false) -> Button:
	var button: Button = _new_slide() if slide else Button.new()
	if primary:
		button.theme_type_variation = &"PrimaryButton"
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.pressed.connect(on_pressed)
	(container if container != null else _actions).add_child(button)
	_refreshers.append(func() -> void:
		if visible_provider.is_valid():
			button.visible = visible_provider.call()
			if not button.visible:
				return
		# Wyszarzony przycisk bez slowa wyjasnienia wyglada jak zepsuty —
		# wlasciciel zglosil rozbudowe inkubatora jako "nie dziala", a po
		# prostu brakowalo mu pieniedzy. Dopisujemy, ile. Dopisek liczymy
		# ZAWSZE od swiezego napisu, nigdy od poprzedniej zawartosci
		# przycisku — inaczej dokleja sie przy kazdym odswiezeniu i kwota
		# rosnie w nieskonczonosc.
		var base: String = text_provider.call()
		button.disabled = not enabled_provider.call()
		if button.disabled and price_provider.is_valid() and Game.state != null:
			var brak: float = float(price_provider.call()) - Game.state.money
			if brak > 0.0:
				if button is SlideButton and (button as SlideButton).compact:
					base += " · " + tr("PANEL_MISSING_SHORT") % NumberFormat.money(brak)
				else:
					base += "\n" + tr("PANEL_MISSING_MONEY") % NumberFormat.money(brak)
		button.text = base)
	return button


func _new_slide() -> SlideButton:
	var slide := SlideButton.new()
	slide.tapped_only.connect(func() -> void: _flash(tr("PANEL_SLIDE_HINT")))
	return slide


## Rozbudowa budynku na samej gorze panelu. Wlasciciel 25.11: suwak na JEDNA
## linijke ("Rozbuduj za 3 000 zl · budowa 8 min"), a nazwa i to, co daje
## nastepny poziom, malym szarym drukiem nad nim. W trakcie budowy - pasek
## postepu z czasem do konca (czas ziemski). `effect_provider(upgrade)` mowi,
## co daje nastepny poziom ("55 miejsc dla ptakow").
func _add_upgrade(building_id: String, effect_provider: Callable) -> void:
	var next := _small_note()
	_upgrades.add_child(next)
	_refreshers.append(func() -> void:
		var upgrade := Game.state.upgrade_entry(building_id)
		next.visible = not upgrade.is_empty() and not Game.state.is_building(building_id)
		if next.visible:
			next.text = tr("PANEL_UPGRADE_NEXT") % [String(upgrade.get("name", "")),
					effect_provider.call(upgrade)])
	var slide := _add_action(true,
			func() -> bool: return not Game.state.is_building(building_id) \
					and Game.upgrade_block_reason(building_id).is_empty() and Game.state.money \
					>= float(Game.state.upgrade_entry(building_id).get("price", 0)),
			func() -> String:
				if Game.state.is_building(building_id):
					return tr("PANEL_BUILDING_BUSY") % NumberFormat.duration(
							Game.state.construction_left(building_id))
				var blocked := Game.upgrade_block_reason(building_id)
				if not blocked.is_empty():
					return blocked
				return tr("PANEL_UPGRADE_SLIDE") % [NumberFormat.money(float(
						Game.state.upgrade_entry(building_id).get("price", 0))),
						_build_time_text(building_id)],
			func() -> void: _on_upgrade(building_id),
			func() -> bool: return not Game.state.upgrade_entry(building_id).is_empty(),
			func() -> float:
				if Game.state.is_building(building_id):
					return 0.0
				return float(Game.state.upgrade_entry(building_id).get("price", 0)),
			_upgrades, true)
	_make_compact(slide as SlideButton)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var head := HBoxContainer.new()
	var label := Label.new()
	label.theme_type_variation = &"NoteLabel"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	var detail := Label.new()
	detail.theme_type_variation = &"CounterLabel"
	head.add_child(label)
	head.add_child(detail)
	var bar := ProgressBar.new()
	bar.max_value = 1.0
	bar.step = 0.001
	bar.show_percentage = false
	bar.custom_minimum_size.y = 30
	box.add_child(head)
	box.add_child(bar)
	_upgrades.add_child(box)
	_refreshers.append(func() -> void:
		box.visible = Game.state.is_building(building_id)
		if not box.visible:
			return
		label.text = tr("PANEL_BUILDING") % String(
				Game.state.upgrade_entry(building_id).get("name", ""))
		detail.text = NumberFormat.clock(Game.state.construction_left(building_id))
		bar.value = Game.state.construction_progress(building_id))


## Plot i pies: kupuje sie je od reki, bez budowy. Tak samo jak rozbudowa -
## maly szary opis nad niskim suwakiem "Kup psa za 400 zl".
func _add_purchase(building_id: String, slide_key: String, effect_provider: Callable) -> void:
	var next := _small_note()
	_upgrades.add_child(next)
	_refreshers.append(func() -> void:
		var upgrade := Game.state.next_building_upgrade(building_id)
		next.visible = not upgrade.is_empty()
		if next.visible:
			next.text = effect_provider.call(upgrade))
	var slide := _add_action(false,
			func() -> bool: return Game.state.money >= float(
					Game.state.next_building_upgrade(building_id).get("price", 0)),
			func() -> String: return tr(slide_key) % NumberFormat.money(float(
					Game.state.next_building_upgrade(building_id).get("price", 0))),
			func() -> void: _on_upgrade(building_id),
			func() -> bool: return not Game.state.next_building_upgrade(building_id).is_empty(),
			func() -> float: return float(Game.state.next_building_upgrade(building_id).get("price", 0)),
			_upgrades, true)
	_make_compact(slide as SlideButton)


## Maly szary opis nad suwakiem (nazwa i dzialanie tego, co sie kupuje).
func _small_note() -> Label:
	var note := Label.new()
	note.theme_type_variation = &"NoteLabel"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 26)
	note.add_theme_color_override("font_color", Color("#7A6A5C"))
	return note


## Nazwa posiadanego plotu albo psa - prosto z data/rozbudowy.json.
func _owned_name(building_id: String, level: int) -> String:
	var ups: Array = GameData.balance().get("buildings", {}).get(building_id, {}).get("upgrades", [])
	if level <= 0 or ups.is_empty():
		return ""
	return String((ups[mini(level, ups.size()) - 1] as Dictionary).get("name", ""))


## Czas budowy nastepnego poziomu w zwyklym zdaniu ("budowa 12 min").
func _build_time_text(building_id: String) -> String:
	var seconds := Game.state.build_seconds(building_id)
	return tr("PANEL_UPGRADE_TIME") % NumberFormat.duration(seconds) if seconds > 0.0 else ""


## Nazwa obecnego poziomu: start ma nazwe w samym budynku ("name"),
## kolejne poziomy - w swoich wpisach upgrades[].
func _level_name(building_id: String) -> String:
	var cfg: Dictionary = GameData.balance().get("incubator", {}) if building_id == "incubator" \
			else GameData.balance().get("buildings", {}).get(building_id, {})
	var level := Game.state.building_level(building_id)
	if level <= 0:
		return tr(String(cfg.get("name", "")))
	var ups: Array = cfg.get("upgrades", [])
	return tr(String((ups[mini(level, ups.size()) - 1] as Dictionary).get("name", "")))


## Pasza: zuzycie na godzine ZEGARA i na jak dlugo starczy.
func _add_feed_time_rows() -> void:
	_add_row("PANEL_FEED_BURN",
			func() -> String:
				var per_hour := Game.state.feed_per_minute() * 60.0 * GameData.time_scale()
				return tr("PANEL_FEED_BURN_VALUE") % NumberFormat.amount_only(per_hour))
	_add_row("PANEL_FEED_LASTS",
			func() -> String:
				var per_min := Game.state.feed_per_minute()
				if Game.state.feed <= 0.0:
					return tr("PANEL_FEED_GONE")
				if per_min <= 0.0:
					return "—"
				# feed_per_minute jest na minute GRY; zamieniamy na zegar.
				var game_seconds := Game.state.feed / per_min * 60.0
				return NumberFormat.duration(game_seconds / GameData.time_scale()))


## Ile czasu ZIEMSKIEGO minelo na farmie (z licznika dni gry).
func _farm_age() -> float:
	var day := float(GameData.balance().get("day", {}).get("seconds", 600.0))
	return (Game.state.days + Game.state.day_fraction) * day / maxf(0.0001, GameData.time_scale())


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
	var sold := mini(Game.egg_sale_lot(), Game.state.egg_count())
	var earned := Game.sell_eggs(sold)
	if earned > 0.0:
		_flash(tr("PANEL_SOLD") % [NumberFormat.eggs(sold), NumberFormat.money(earned)])


## Ferma admina 000000: poziom w gore/dol za darmo (w kurniku tez plot i pies).
func _add_admin_levels(building_id: String) -> void:
	var ids: Array[String] = [building_id]
	if building_id == "coop":
		ids.append_array(["guard", "dog"])
	for id in ids:
		var row := HBoxContainer.new()
		row.name = "Admin_%s" % id
		row.add_theme_constant_override("separation", 12)
		for delta: int in [1, -1]:
			var b := _grid_button(&"")
			b.text = "ADMIN %s lvl %s" % [id, "up" if delta > 0 else "down"]
			b.pressed.connect(func() -> void:
				Game.admin_change_level(id, delta)
				_refresh())
			row.add_child(b)
		_upgrades.add_child(row)


## Ile jaj idzie pod przycisk "sprzedaj 80%" (najstarsze najpierw).
func _eggs_share_count() -> int:
	return int(floor(Game.state.egg_count() * 0.8))


func _on_sell_eggs_share() -> void:
	var sold := _eggs_share_count()
	if sold <= 0:
		return
	var earned := Game.sell_eggs(sold)
	if earned > 0.0:
		_flash(tr("PANEL_SOLD") % [NumberFormat.eggs(sold), NumberFormat.money(earned)])


func _on_buy_feed(option: int = 0) -> void:
	if Game.buy_feed(option):
		_flash(tr("PANEL_FEED_BOUGHT"))


## Kupno idzie suwakiem (od 12.19) - droga rasa to tysiace zlotych, a
## przycisk stoi tuz obok sprzedazy. Okienko "na pewno?" bylo za ciezkie.
func _on_buy_hen(breed_id: String, breed_name: String, rooster: bool = false) -> void:
	_do_buy_hen(breed_id, breed_name, rooster)


func _do_buy_hen(breed_id: String, breed_name: String, rooster: bool) -> void:
	if Game.buy_hen(breed_id, rooster):
		var key := "PANEL_ROOSTER_BOUGHT" if rooster else "PANEL_HEN_BOUGHT"
		_flash(tr(key) % breed_name)


## Ubija chora sztuke. Najpierw kury, a koguta dopiero wtedy, gdy to on jest
## chory — inaczej jedno nieuwazne stukniecie zostawialoby rase bez koguta.
func _on_cull_hen(breed_id: String, breed_name: String) -> void:
	var rooster := not Game.has_sick(breed_id)
	if Game.cull_hen(breed_id, rooster):
		_flash(tr("PANEL_HEN_MCDONALDS") % [breed_name, NumberFormat.money(Game.mcdonalds_price())])


## Sprzedaz ptaka: od 12.22 zwykle dotkniecie (wlasciciel 25.11 - suwaki
## tylko przy kupnie).
func _on_sell_hen(breed_id: String, breed_name: String, rooster: bool = false) -> void:
	_do_sell_hen(breed_id, breed_name, rooster)


func _do_sell_hen(breed_id: String, breed_name: String, rooster: bool) -> void:
	var earned := Game.sell_hen(breed_id, rooster)
	if earned > 0.0:
		var key := "PANEL_ROOSTER_SOLD" if rooster else "PANEL_HEN_SOLD"
		_flash(tr(key) % [breed_name, NumberFormat.money(earned)])


func _on_buy_vaccine() -> void:
	if not Game.buy_vaccine():
		_flash(tr("PANEL_NO_MONEY"))


func _on_upgrade(building_id: String) -> void:
	if not Game.upgrade_building(building_id):
		_flash(tr("PANEL_NO_MONEY"))
		return
	_refresh()


## Pole do przepisania kodu farmy z innego urzadzenia. To jedyna droga
## powrotu do swojej gry po wyczyszczeniu danych przegladarki, wiec siedzi
## w magazynie, tuz pod kodem wlasnej farmy.
func _add_code_entry() -> void:
	var hint := Label.new()
	hint.theme_type_variation = &"NoteLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = tr("PANEL_CODE_HINT")
	_actions.add_child(hint)

	# Wlasna klawiatura numeryczna zamiast pola tekstowego: klawiatura
	# systemowa na telefonie nie wpuszczala cyfr do gry.
	var keypad := CodeKeypad.new()
	_actions.add_child(keypad)

	var button := Button.new()
	button.theme_type_variation = &"BuyButton"
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.text = tr("PANEL_CODE_LOAD")
	_actions.add_child(button)

	# Przycisk diagnostyczny: jedno pytanie do serwera i jednozdaniowa
	# odpowiedz, co dokladnie nie dziala. Bez tego "brak polaczenia" zmuszalo
	# do zgadywania miedzy brakiem tabeli, brakiem uprawnien i brakiem sieci.
	var check := Button.new()
	check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	check.text = tr("PANEL_SERVER_CHECK")
	_actions.add_child(check)

	# Odpowiedz serwera pokazujemy tutaj, pod przyciskiem. Sam pasek
	# z komunikatem bywal zaslaniany przez panel i gracz po wpisaniu kodu
	# nie widzial zupelnie nic.
	var status := Label.new()
	status.theme_type_variation = &"NoteLabel"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.visible = false
	_actions.add_child(status)
	# Etykieta znika razem z przebudowa panelu, a polaczenie z Events.notice
	# zostaje — bez sprawdzenia lambda siega po skasowany wezel. Wyszlo przy
	# rozbudowie inkubatora, ktora przebudowuje panel w trakcie dzialania.
	var say := func(text: String) -> void:
		if not is_instance_valid(status):
			return
		status.text = text
		status.visible = not text.is_empty()
	Events.notice.connect(func(text: String) -> void:
		if is_instance_valid(status) and is_open():
			say.call(text))

	button.pressed.connect(func() -> void:
		say.call(tr("START_LOADING"))
		if Game.restore_from_code(keypad.code()):
			keypad.clear())

	check.pressed.connect(func() -> void:
		say.call(tr("START_LOADING"))
		Cloud.pull())
	Cloud.pulled.connect(func(_payload: Dictionary, _ok: bool, _who: String) -> void:
		if is_open():
			say.call(Cloud.describe_last()))
	keypad.submitted.connect(func(_code: String) -> void: button.emit_signal("pressed"))


## Ile kur danej rasy ma gracz.
func _owned(breed_id: String) -> int:
	return int(Game.state.hens_by_breed().get(breed_id, 0))


## Pasek postepu, ktory sam sie chowa, gdy nie ma czego pokazywac.
##
## Nazwa stoi po lewej, a `detail_provider` (np. "47% · 2 min") po prawej —
## dokladnie tak, jak w zwyklych wierszach panelu, zeby kolumna liczb byla
## wszedzie w tym samym miejscu. Koledzy zglosili, ze gole paski wygladaly
## na puste i nie mowily, ile jeszcze zostalo.
func _add_progress_dynamic(label_provider: Callable, value_provider: Callable,
		detail_provider: Callable = Callable()) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var head := HBoxContainer.new()
	var label := Label.new()
	label.theme_type_variation = &"NoteLabel"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	var detail := Label.new()
	detail.theme_type_variation = &"CounterLabel"
	head.add_child(label)
	head.add_child(detail)
	var bar := ProgressBar.new()
	bar.max_value = 1.0
	bar.step = 0.001
	bar.show_percentage = false
	bar.custom_minimum_size.y = 30
	box.add_child(head)
	box.add_child(bar)
	_bars.add_child(box)
	_refreshers.append(func() -> void:
		var text: String = label_provider.call()
		box.visible = text != ""
		if not box.visible:
			return
		label.text = text
		detail.text = detail_provider.call() if detail_provider.is_valid() else ""
		bar.value = value_provider.call())


## Naglowek grupy w panelu; chowa sie, gdy `visible_provider` zwroci false.
func _add_group(label_key: String, visible_provider: Callable) -> void:
	var label := Label.new()
	label.text = tr(label_key)
	label.theme_type_variation = &"GroupLabel"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bars.add_child(label)
	_refreshers.append(func() -> void: label.visible = visible_provider.call())


## Wiersz "Poziom: 2 / 6". Poziom poczatkowy liczymy jako pierwszy, bo
## "0 / 5" gracz czyta jako brak budynku. `levels` to liczba poziomow razem
## z poczatkowym.
func _add_level_row(level_provider: Callable, levels: int,
		name_provider: Callable = Callable()) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = tr("PANEL_LEVEL")
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value := Label.new()
	value.theme_type_variation = &"CounterLabel"
	_row_value(value)
	# 12.31 (wlasciciel 26.11): numer poziomu w kolku jak liczba kur w sklepie,
	# bez "/ 10" - kazdy budynek ma tyle samo poziomow, wiec to zbedne.
	var badge := _count_badge(Color("#B7791F"))
	badge.name = "LevelBadge"
	row.add_child(label)
	row.add_child(value)
	row.add_child(badge)
	row.add_theme_constant_override("separation", 12)
	_rows.add_child(row)
	_refreshers.append(func() -> void:
		var shown: int = int(level_provider.call()) + 1
		(badge.get_child(0) as Label).text = str(shown)
		# Przy nazwanych poziomach ("duży inkubator") sam numer nic nie mowi.
		var named: String = name_provider.call() if name_provider.is_valid() else ""
		if shown >= levels:
			named = tr("PANEL_LEVEL_TOP") if named.is_empty() \
					else "%s · %s" % [named, tr("PANEL_LEVEL_TOP")]
		value.text = named)


## Ile poziomow ma budynek razem z poczatkowym.
func _building_levels(building_id: String) -> int:
	var upgrades: Array = GameData.balance().get("buildings", {}) \
			.get(building_id, {}).get("upgrades", [])
	return upgrades.size() + 1


## Sekundy GRY zamienione na czas, ktory gracz naprawde odczeka, i zapisane
## po polsku. Czas w grze plynie wolniej niz zegarek, wiec bez tego dzielenia
## "jeszcze 2 min" klamaloby o trzykrotnosc.
func _countdown(game_seconds: float) -> String:
	return NumberFormat.duration(game_seconds / maxf(0.001, GameData.time_scale()))


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
	picture.custom_minimum_size = Vector2(170, 170)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture = _breed_image(breed)
	# Zdjecia realnych kur sa prostokatne — obcinamy je do kwadratu karty.
	picture.clip_contents = true
	top.add_child(picture)

	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 4)
	var title := Label.new()
	title.text = breed_name
	# 12.24/12.25 (wlasciciel 25.11): ile masz - cyferka w ciemnozielonym kolku
	# obok nazwy rasy (kury), a obok kogucik i ciemnoczerwone kolko (koguty).
	var name_row := HBoxContainer.new()
	name_row.name = "NameRow"
	name_row.add_theme_constant_override("separation", 10)
	name_row.add_child(title)
	var hen_badge := _count_badge(Color("#2F5A1E"))
	hen_badge.name = "HenBadge"
	name_row.add_child(hen_badge)
	var cock_icon := TextureRect.new()
	cock_icon.custom_minimum_size = Vector2(40, 40)
	cock_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cock_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cock_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var cock_path := String(breed.get("rooster_sprite", ""))
	if cock_path != "" and ResourceLoader.exists(cock_path):
		cock_icon.texture = load(cock_path) as Texture2D
	name_row.add_child(cock_icon)
	var cock_badge := _count_badge(Color("#8E1B1B"))
	cock_badge.name = "RoosterBadge"
	name_row.add_child(cock_badge)
	var subtitle := Label.new()
	subtitle.theme_type_variation = &"NoteLabel"
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var numbers := Label.new()
	numbers.theme_type_variation = &"NoteLabel"
	numbers.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	texts.add_child(name_row)
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

	# Rasa zamknieta za poziomem kurnika: malutki szary dopisek zamiast
	# zawijanego napisu na przyciskach (wlasciciel 25.11).
	var locked_note := Label.new()
	locked_note.name = "LockedNote"
	locked_note.add_theme_font_size_override("font_size", 22)
	locked_note.add_theme_color_override("font_color", Color("#9A8C80"))
	locked_note.add_theme_constant_override("line_spacing", 0)
	card.add_child(locked_note)

	# Dwie kolumny (wlasciciel 25.11): po lewej kupno, po prawej sprzedaz.
	#   Kup kure    | Sprzedaj kure
	#   Kup koguta  | Sprzedaj koguta
	# Polowa szerokosci to od razu krotszy suwak. Sprzedaz zostaje widoczna
	# (wyszarzona, gdy nie ma czego sprzedac), zeby kolumny sie nie rozjezdzaly.
	# 12.22 (wlasciciel 25.11): suwak tylko przy KUPNIE; sprzedaz to zwykly
	# niski przycisk - jedno dotkniecie, jedna sztuka.
	var buy := _grid_slide(&"BuyButton")
	buy.pressed.connect(func() -> void: _on_buy_hen(breed_id, breed_name))
	var sell := _grid_button(&"SellButton")
	sell.pressed.connect(func() -> void: _on_sell_hen(breed_id, breed_name))
	var buy_rooster := _grid_slide(&"BuyButton")
	buy_rooster.pressed.connect(func() -> void: _on_buy_hen(breed_id, breed_name, true))
	var sell_rooster := _grid_button(&"SellButton")
	sell_rooster.pressed.connect(func() -> void: _on_sell_hen(breed_id, breed_name, true))
	for pair: Array in [[buy, sell], [buy_rooster, sell_rooster]]:
		var row := HBoxContainer.new()
		row.name = "Trade"
		row.add_theme_constant_override("separation", 12)
		for button: Button in pair:
			row.add_child(button)
		card.add_child(row)

	# Chora sztuke mozna oddac do skupu za drobne - leku nie ma (12.20).
	# To swiadomy zart wlasciciela, nie przeoczenie. To tez sprzedaz, wiec
	# od 12.22 zwykly przycisk, bez suwaka.
	var cull := _grid_button(&"CullButton")
	cull.pressed.connect(func() -> void: _on_cull_hen(breed_id, breed_name))
	card.add_child(cull)

	_actions.add_child(card)

	_refreshers.append(func() -> void:
		var owned := _owned(breed_id)
		var cocks := Game.state.hens_of_breed(breed_id, false, true)
		var poor := Game.state.money < price
		# Licznik "(masz N szt.)" jak przy kogucie i przy sprzedazy — bez niego
		# to jedyny przycisk w sklepie, ktory nie mowi, ile masz.
		# Rasa zamknieta za poziomem kurnika mowi wprost, czego brakuje —
		# wyszarzony przycisk bez wyjasnienia wyglada jak zepsuty.
		var locked := not Game.breed_allowed(breed_id)
		# Kogut ma wlasna, wyzsza cene — i wlasny warunek "nie stac Cie".
		var cock_price := FarmState.hen_buy_price(breed_id, true)
		locked_note.visible = locked
		if locked:
			locked_note.text = tr("PANEL_BREED_LOCKED") % Game.breed_required_level(breed_id)
		# Ile masz - wprost na przyciskach kupna, krotko (wlasciciel 25.11:
		# w opisie pod nazwa rasy bylo to za malo widoczne).
		buy.text = tr("PANEL_BUY_HEN") % NumberFormat.money(price)
		buy_rooster.text = tr("PANEL_BUY_ROOSTER") % NumberFormat.money(cock_price)
		(hen_badge.get_child(0) as Label).text = str(owned)
		(cock_badge.get_child(0) as Label).text = str(cocks)
		buy.disabled = poor or locked
		# Wczesniej ta linijka byla pisana dwa razy i druga gubila `locked`,
		# wiec koguta dalo sie kupic do rasy zamknietej za poziomem kurnika.
		buy_rooster.disabled = locked or Game.state.money < cock_price
		no_rooster.visible = owned > 0 and cocks == 0
		# Skup bierze tylko zdrowe sztuki, wiec licznik na przycisku sprzedazy
		# pokazuje zdrowe, a nie cale stado tej rasy.
		var healthy := Game.state.hens_of_breed(breed_id, true)
		var healthy_cocks := Game.state.hens_of_breed(breed_id, true, true)
		sell.disabled = healthy <= 0
		sell.text = tr("PANEL_SELL_HEN") % NumberFormat.money(FarmState.hen_sell_price(breed_id))
		sell_rooster.disabled = healthy_cocks <= 0
		sell_rooster.text = tr("PANEL_SELL_ROOSTER") % NumberFormat.money(
				FarmState.hen_sell_price(breed_id, false, true))
		var sick := owned - healthy + cocks - healthy_cocks
		cull.visible = sick > 0
		cull.text = tr("PANEL_CULL_HEN") % [NumberFormat.money(Game.mcdonalds_price()), sick]
		subtitle.text = "%s · %s" % [tr(breed.get("rarity", "")), tr(breed.get("desc", ""))]
		# Pospolite jaja ida do sklepu na jedzenie, reszta jako legowe do
		# hodowcow (wlasciciel 26.11) - stad dwa podpisy.
		var egg_key := "PANEL_BREED_NUMBERS" if breed.get("rarity", "") == "RARITY_COMMON" \
				else "PANEL_BREED_NUMBERS_HATCH"
		numbers.text = tr(egg_key) % [
			NumberFormat.small_money(FarmState.egg_value(breed_id)),
			NumberFormat.duration(float(breed.get("egg_seconds", 0)) / GameData.time_scale())])


## Suwak do siatki kupna i sprzedazy na karcie rasy: pol szerokosci karty.
func _grid_slide(variation: StringName) -> SlideButton:
	var slide := _new_slide()
	slide.theme_type_variation = variation
	slide.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slide.size_flags_stretch_ratio = 1.0
	_make_compact(slide)
	# Bez minimalnej szerokosci dluzszy napis rozpychalby swoja kolumne.
	slide.custom_minimum_size.x = 10.0
	return slide


## Kolko z liczba sztuk obok nazwy rasy w sklepie (bialy pogrubiony napis
## na ciemnym tle, dobrze widoczny).
func _count_badge(color: Color) -> PanelContainer:
	var badge := PanelContainer.new()
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.custom_minimum_size = Vector2(44, 44)
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(22)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 0
	box.content_margin_bottom = 0
	badge.add_theme_stylebox_override("panel", box)
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color.WHITE)
	badge.add_child(label)
	return badge


## Zwykly przycisk do siatki sklepu, tej samej wysokosci co suwaki obok:
## sprzedaz bez suwaka (12.22).
func _grid_button(variation: StringName) -> Button:
	var button := Button.new()
	button.theme_type_variation = variation
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_stretch_ratio = 1.0
	button.autowrap_mode = TextServer.AUTOWRAP_OFF
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.add_theme_font_size_override("font_size", 30)
	button.custom_minimum_size = Vector2(10.0, 72.0)
	# Styl przycisku sklepu ma grube marginesy (~83 px wysokosci) i rozpychal
	# wiersz razem z suwakiem obok. Kopie stylow z cienszymi marginesami.
	button.ready.connect(func() -> void:
		for state_name: String in ["normal", "hover", "pressed", "disabled", "focus"]:
			var box := button.get_theme_stylebox(state_name)
			if box == null:
				continue
			var thin := box.duplicate() as StyleBox
			thin.content_margin_top = 4.0
			thin.content_margin_bottom = 4.0
			button.add_theme_stylebox_override(state_name, thin))
	return button


## Niski suwak na jedna linijke tekstu (wlasciciel 25.11: "male slajdery na
## jedna linijke"). Bez zawijania, mniejsza czcionka, wysokosc ~72 px.
func _make_compact(slide: SlideButton) -> void:
	slide.compact = true
	slide.autowrap_mode = TextServer.AUTOWRAP_OFF
	slide.clip_text = true
	slide.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	slide.add_theme_font_size_override("font_size", 30)
	slide.custom_minimum_size.y = 72.0


## Grafika rasy w sklepie: ta sama postac co na wybiegu (wlasciciel 25.11 -
## malowane portrety sa tylko w oknie nowej rasy i w Osiagnieciach).
func _breed_image(breed: Dictionary) -> Texture2D:
	var photo: String = breed.get("photo", "")
	if photo != "" and ResourceLoader.exists(photo):
		return load(photo) as Texture2D
	return load(breed.get("sprite", "")) as Texture2D


## Czego brakuje do odblokowania rasy, po przecinku.

func _on_incubate(breed_id: String) -> void:
	if Game.incubate(breed_id):
		_flash(tr("PANEL_EGGS_IN"))

