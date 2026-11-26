extends Control
## OSIAGNIECIA (12.21, wlasciciel 25.11): album kart ras jak karty w Wiedzminie.
## Gwiazdka w lewym gornym rogu otwiera siatke kart. Zdobyta rasa (kupiona
## albo wykluta choc raz - FarmState.unlocked_breeds) pokazuje malowany
## portret; dotkniecie otwiera wielka karte z historia i ciekawostkami
## (UnlockPanel.show_card). Niezdobyta to ciemna sylwetka i znaki zapytania.
##
## INNE FERMY (12.30, wlasciciel 26.11): przycisk na gorze pokazuje liste ferm
## z serwera z kodami - najpierw fermy z tego urzadzenia, potem pozostalych
## graczy. Dotkniecie kodu pokazuje karty tamtej fermy. To tylko podglad:
## nic nie wczytuje i nie zmienia kodu urzadzenia.

const COLUMNS := 3

var _grid: GridContainer
var _count: Label
var _farm_label: Label
var _farms_button: Button
var _grid_scroll: ScrollContainer
var _list_scroll: ScrollContainer
var _list: VBoxContainer
## Kod podgladanej cudzej fermy; pusty = biezaca ferma z Game.state.
var _viewing := ""
var _viewing_unlocked: Array = []
var _listing := false
## Zdobyte karty z ostatnio pobranej listy ferm: kod -> Array id ras.
var _cached_unlocked := {}
var _star: Button
## Miejsce w drzewie HUD-u, do ktorego wracamy po zamknieciu (pod panelami
## budynkow - inaczej gwiazdka wisialaby nad otwartym sklepem).
var _home_index := -1


func _ready() -> void:
	name = "AchievementsPanel"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_star()
	_build_sheet()
	$Sheet.hide()
	$Dim.hide()
	(func() -> void: _home_index = get_index()).call_deferred()


## Gwiazdka nad drzewami, pod paskiem licznikow.
func _build_star() -> void:
	_star = Button.new()
	_star.name = "Star"
	# Bez tekstu: gwiazdke rysuje StarIcon (w czcionce nie ma znaku "★").
	_star.text = ""
	_star.tooltip_text = tr("ACH_TITLE")
	_star.position = Vector2(24, 118)
	_star.size = Vector2(112, 112)
	_star.custom_minimum_size = Vector2(112, 112)
	_star.add_theme_font_size_override("font_size", 68)
	for state_name: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_star.add_theme_color_override(state_name, Color("#F2B233"))
	_star.add_theme_color_override("font_outline_color", Color("#7A4A12"))
	_star.add_theme_constant_override("outline_size", 8)
	var round_box := StyleBoxFlat.new()
	round_box.bg_color = Color(1.0, 0.98, 0.92, 0.92)
	round_box.set_corner_radius_all(56)
	round_box.set_border_width_all(5)
	round_box.border_color = Color("#C98A2E")
	round_box.shadow_color = Color(0.3, 0.2, 0.1, 0.35)
	round_box.shadow_size = 6
	for state_name: String in ["normal", "hover", "pressed", "focus"]:
		_star.add_theme_stylebox_override(state_name, round_box)
	_star.mouse_filter = Control.MOUSE_FILTER_STOP
	_star.pressed.connect(open)
	var icon := StarIcon.new()
	icon.name = "StarIcon"
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 14
	icon.offset_top = 12
	icon.offset_right = -14
	icon.offset_bottom = -16
	_star.add_child(icon)
	add_child(_star)


func _build_sheet() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.19, 0.12, 0.07, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var sheet := PanelContainer.new()
	sheet.name = "Sheet"
	sheet.set_anchors_preset(Control.PRESET_CENTER)
	sheet.offset_left = -520
	sheet.offset_right = 520
	sheet.offset_top = -900
	sheet.offset_bottom = 900
	add_child(sheet)

	var box := VBoxContainer.new()
	box.name = "Content"
	box.add_theme_constant_override("separation", 14)
	sheet.add_child(box)

	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text = tr("ACH_TITLE")
	box.add_child(title)

	_farm_label = Label.new()
	_farm_label.name = "FarmLabel"
	_farm_label.theme_type_variation = &"GroupLabel"
	_farm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_farm_label)

	_farms_button = Button.new()
	_farms_button.name = "FarmsButton"
	_farms_button.custom_minimum_size = Vector2(0, 90)
	_farms_button.pressed.connect(_on_farms_button)
	box.add_child(_farms_button)

	_count = Label.new()
	_count.name = "Count"
	_count.theme_type_variation = &"NoteLabel"
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_count)

	var scroll := ScrollContainer.new()
	scroll.name = "GridScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_grid_scroll = scroll
	_list_scroll = ScrollContainer.new()
	_list_scroll.name = "FarmsScroll"
	_list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_scroll.hide()
	box.add_child(_list_scroll)
	_list = VBoxContainer.new()
	_list.name = "Farms"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 12)
	_list_scroll.add_child(_list)
	_grid = GridContainer.new()
	_grid.name = "Grid"
	_grid.columns = COLUMNS
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(_grid)

	var close := Button.new()
	close.name = "Close"
	close.theme_type_variation = &"PrimaryButton"
	close.text = tr("ACH_CLOSE")
	close.custom_minimum_size = Vector2(0, 100)
	close.pressed.connect(close_panel)
	box.add_child(close)


func open() -> void:
	_viewing = ""
	_viewing_unlocked = []
	_show_grid()
	get_parent().move_child(self, -1)
	# GAME OVER zostaje na samym wierzchu.
	var over := get_parent().get_node_or_null("GameOverPanel") as Control
	if over != null:
		get_parent().move_child(over, -1)
	mouse_filter = Control.MOUSE_FILTER_STOP
	$Dim.show()
	$Sheet.show()


func close_panel() -> void:
	if _home_index >= 0:
		get_parent().move_child(self, _home_index)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Dim.hide()
	$Sheet.hide()


func is_open() -> bool:
	return $Sheet.visible


func is_listing() -> bool:
	return _listing


func viewing_code() -> String:
	return _viewing


func _fill() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	var have := 0
	var all := GameData.breeds()
	for breed: Dictionary in all:
		var breed_id: String = breed.get("id", "")
		var owned := Game.state.has_ever_owned(breed_id) if _viewing.is_empty() \
				else _viewing_unlocked.has(breed_id)
		if owned:
			have += 1
		_grid.add_child(_card(breed, owned))
	if _viewing.is_empty():
		_count.text = tr("ACH_COUNT") % [have, all.size()]
		_farm_label.text = tr("ACH_MY_FARM_LABEL") % Cloud.player_id
	else:
		_count.text = tr("ACH_COUNT_OTHER") % [have, all.size()]
		_farm_label.text = tr("ACH_OTHER_FARM_LABEL") % _viewing


func _show_grid() -> void:
	_listing = false
	_fill()
	_list_scroll.hide()
	_grid_scroll.show()
	_count.show()
	_grid_scroll.scroll_vertical = 0
	_farms_button.text = tr("ACH_SHOW_FARMS")


func _on_farms_button() -> void:
	if _listing:
		_show_grid()
		return
	_listing = true
	_grid_scroll.hide()
	_count.hide()
	_list_scroll.show()
	_farms_button.text = tr("ACH_BACK_TO_CARDS")
	_farm_label.text = tr("ACH_FARMS_TITLE")
	_clear_list()
	_list.add_child(_note(tr("ACH_FARMS_LOADING")))
	if not Cloud.farms_listed.is_connected(_on_farms_listed):
		Cloud.farms_listed.connect(_on_farms_listed, CONNECT_ONE_SHOT)
	Cloud.list_farms()


func _clear_list() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()


func _note(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"NoteLabel"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text = text
	return label


func _on_farms_listed(rows: Array, ok: bool) -> void:
	if not _listing:
		return
	_clear_list()
	if not ok:
		_list.add_child(_note(tr("ACH_FARMS_FAILED")))
		return
	var by_code := {}
	_cached_unlocked.clear()
	for row: Dictionary in rows:
		by_code[String(row.get("player_id", ""))] = row
		_cached_unlocked[String(row.get("player_id", ""))] = row.get("unlocked", [])
	var mine := Cloud.my_farms()
	var total := GameData.breeds().size()
	var title_mine := Label.new()
	title_mine.theme_type_variation = &"GroupLabel"
	title_mine.text = tr("ACH_FARMS_MINE")
	_list.add_child(title_mine)
	for code: String in mine:
		if code == Cloud.player_id:
			_list.add_child(_farm_row(code, Game.state.unlocked_breeds.size(), total, 0, true))
		elif by_code.has(code):
			var row: Dictionary = by_code[code]
			_list.add_child(_farm_row(code, (row["unlocked"] as Array).size(), total,
					int(row["updated_at"]), false))
	var title_others := Label.new()
	title_others.theme_type_variation = &"GroupLabel"
	title_others.text = tr("ACH_FARMS_OTHERS")
	_list.add_child(title_others)
	var others := 0
	for row: Dictionary in rows:
		var code := String(row.get("player_id", ""))
		if code.is_empty() or mine.has(code):
			continue
		others += 1
		_list.add_child(_farm_row(code, (row["unlocked"] as Array).size(), total,
				int(row["updated_at"]), false))
	if others == 0:
		_list.add_child(_note(tr("ACH_FARMS_NONE")))


func _farm_row(code: String, have: int, total: int, updated_at: int, current: bool) -> Button:
	var button := Button.new()
	button.name = "Farm_" + code
	button.custom_minimum_size = Vector2(0, 96)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if current:
		button.text = tr("ACH_FARM_ROW_CURRENT") % [code, have, total]
	else:
		button.text = tr("ACH_FARM_ROW") % [code, have, total, _when(updated_at)]
	button.pressed.connect(func() -> void: _view_farm(code, current))
	return button


## Data ostatniego zapisu w czasie lokalnym, np. "26.11, 13:05".
func _when(unix: int) -> String:
	if unix <= 0:
		return "?"
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	var d := Time.get_datetime_dict_from_unix_time(unix + bias * 60)
	return "%02d.%02d, %02d:%02d" % [d["day"], d["month"], d["hour"], d["minute"]]


func _view_farm(code: String, current: bool) -> void:
	_viewing = "" if current else code
	_viewing_unlocked = []
	if not current:
		# Karty bierzemy z tej samej listy - nie trzeba pytac serwera drugi raz.
		_viewing_unlocked = _cached_unlocked.get(code, [])
	_show_grid()


## Jedna karta w siatce. Zdobyta: portret w zlotej ramce i nazwa. Niezdobyta:
## sylwetka, "???" i rzadkosc rasy.
func _card(breed: Dictionary, owned: bool) -> Control:
	var breed_id: String = breed.get("id", "")
	var card := Button.new()
	card.name = "Card_" + breed_id
	card.custom_minimum_size = Vector2(250, 360)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color("#FFF8EA") if owned else Color("#E9E2D6")
	frame.set_corner_radius_all(16)
	frame.set_border_width_all(6)
	frame.border_color = Color("#E0A93E") if owned else Color("#B7AA98")
	for state_name: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		card.add_theme_stylebox_override(state_name, frame)
	card.disabled = not owned

	var inner := VBoxContainer.new()
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = 12
	inner.offset_right = -12
	inner.offset_top = 12
	inner.offset_bottom = -10
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_theme_constant_override("separation", 6)
	card.add_child(inner)

	var pic := TextureRect.new()
	pic.name = "Portrait"
	pic.custom_minimum_size = Vector2(0, 240)
	pic.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var path: String = breed.get("portrait", "")
	if not path.is_empty() and ResourceLoader.exists(path):
		pic.texture = load(path)
	if not owned:
		# Sylwetka: ciemny, prawie czarny obraz - widac ksztalt, nie widac rasy.
		pic.modulate = Color(0.16, 0.13, 0.18, 0.85)
	inner.add_child(pic)

	var label := Label.new()
	label.name = "Name"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 26)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = tr(breed.get("name", "")) if owned else "???"
	inner.add_child(label)

	var rarity := Label.new()
	rarity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rarity.add_theme_font_size_override("font_size", 20)
	rarity.add_theme_color_override("font_color", Color("#9A8C80"))
	rarity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rarity.text = tr(breed.get("rarity", "")).to_upper()
	inner.add_child(rarity)

	card.pressed.connect(func() -> void: _open_card(breed_id))
	return card


func _open_card(breed_id: String) -> void:
	var unlock := get_parent().get_node_or_null("UnlockPanel")
	if unlock != null:
		unlock.show_card(breed_id)
