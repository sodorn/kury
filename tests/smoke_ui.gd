extends Node
## Test dymny z oknem: uruchamia scene glowna i sprawdza, czy rozgrywka
## reaguje — budynki otwieraja panel, kury stoja na wybiegu, jajko da sie
## zebrac dotknieciem, a przyciski w sklepie dzialaja. Zapisuje zrzuty ekranu.
##   godot --path . res://tests/smoke_ui.tscn -- <katalog_na_zrzuty>
## Wymaga wyswietlania (na serwerze: xvfb-run).

var _failed := 0
var _out_dir := "user://"
var _main: Node


func _ready() -> void:
	# Odroczone, bo w trakcie _ready() drzewo sceny jest zajete i add_child()
	# na korzeniu zostalby odrzucony.
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0].trim_suffix("/") + "/"

	# Gra wczytuje zapis przy starcie, wiec przed zbudowaniem sceny kasujemy go
	# i zaczynamy od stanu poczatkowego — inaczej kolejne uruchomienia testu
	# dziedziczylyby stado i jaja z poprzedniego.
	SaveGame.clear()
	Game.new_game()

	# Przy wlaczonym serwerze odpowiedz na startowy pull przychodzi po chwili
	# i podmienia stan gry. Czekamy na nia tutaj, zeby nie wpadla w srodek
	# ktoregos testu i nie sprzatnela mu jaj z wybiegu.
	if Cloud.is_enabled():
		await get_tree().create_timer(3.0).timeout
		SaveGame.clear()
		Game.new_game()

	# Udajemy swieze urzadzenie, zeby zobaczyc ekran powitalny. Pierwszy test
	# go zamyka, wiec reszta leci jak zwykle.
	Game.is_new_player = true

	_main = load("res://scenes/main/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	await _frames(20)
	# Symulacja chodzi dalej w tle i przy wolnym renderze (xvfb) potrafi w czasie
	# testu znosić jaja, co psuje liczenia. Na czas testu ja zatrzymujemy
	# i zmieniamy stan recznie.
	Game.set_process(false)
	_shot("farma.png")

	await _test_start_screen()
	await _test_buildings()
	await _test_hens()
	await _test_egg_pickup()
	await _test_shop()
	await _test_incubator_panel()
	await _test_sell_hen()
	await _test_no_feed_notice()
	await _test_unlock_popup()
	await _test_farm_code_restore()

	SaveGame.clear()
	print("TEST DYMNY: %s" % ("OK" if _failed == 0 else "%d BLEDOW" % _failed))
	get_tree().quit(1 if _failed > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  OK   " + label)
	else:
		_failed += 1
		printerr("  BLAD " + label)


func _test_buildings() -> void:
	var panel: Control = _main.get_node("Hud/Root/BuildingPanel")
	var title: Label = panel.get_node("Sheet/Content/Header/Title")
	for def: Dictionary in GameData.buildings():
		var id: String = def["id"]
		var building: Node2D = _main.get_node("Farm/Objects").get_node(id.capitalize())
		await _tap(_canvas_point(building, Vector2(0, -150)))
		await _frames(30)
		_check(panel.is_open() and title.text == tr(def["name"]), "panel budynku '%s'" % id)
		if id == "shop":
			_shot("panel_sklep.png")
		await _tap(Vector2(540, 260))
		await _frames(30)
		_check(not panel.visible, "panel '%s' zamyka sie dotknieciem tla" % id)


func _test_hens() -> void:
	var hens := _nodes_of_type("FarmChicken")
	_check(hens.size() == Game.state.hen_count(), "liczba kur w scenie zgadza sie ze stanem gry")
	var before: Array[Vector2] = []
	for hen: Node2D in hens:
		before.append(hen.position)
	await _frames(90)
	var moved := 0
	for i in hens.size():
		if (hens[i] as Node2D).position.distance_to(before[i]) > 1.0:
			moved += 1
	_check(moved > 0, "kury chodza po wybiegu (ruszylo sie %d z %d)" % [moved, hens.size()])


func _test_egg_pickup() -> void:
	Game.state.eggs_on_ground.append("leghorn")
	Game.state.eggs_on_ground.append("leghorn")
	Events.eggs_laid.emit(2)
	await _frames(20)
	var eggs := _nodes_of_type("GroundEgg")
	_check(eggs.size() == 2, "jajka pojawily sie na wybiegu")
	_shot("jajka.png")
	if eggs.is_empty():
		return
	var stored_before := Game.state.egg_count()
	await _tap(_canvas_point(eggs[0], Vector2(0, -38)))
	await _frames(40)
	_check(Game.state.egg_count() == stored_before + 1, "dotkniecie jajka zwieksza stan magazynu")
	_check(_nodes_of_type("GroundEgg").size() == 1, "zebrane jajko znika z wybiegu")


func _test_shop() -> void:
	Game.state.eggs = {"leghorn": 6}
	Game.state.money = 500.0
	var shop: Node2D = _main.get_node("Farm/Objects/Shop")
	await _tap(_canvas_point(shop, Vector2(0, -150)))
	await _frames(30)
	var actions: VBoxContainer = _main.get_node("Hud/Root/BuildingPanel/Sheet/Content/Scroll/Scrollable/Actions")
	var rows := actions.get_children()
	_check(rows.size() == 5 + GameData.breeds().size(),
			"sklep ma przyciski, notke i karte kazdej rasy (jest %d)" % rows.size())
	if rows.size() < 3:
		return

	var money_before: float = Game.state.money
	(rows[0] as Button).emit_signal("pressed")
	await _frames(10)
	_check(Game.state.egg_count() == 0 and Game.state.money > money_before, "sprzedaz jaj dziala")

	var feed_before: float = Game.state.feed
	(rows[1] as Button).emit_signal("pressed")
	await _frames(10)
	_check(Game.state.feed > feed_before, "zakup paszy dziala")

	# Karta rasy odblokowanej ma widoczny przycisk, zablokowanej nie ma.
	# Karty ras siedza na koncu listy, po przyciskach i notce o szczepieniu.
	var first_card := rows.size() - GameData.breeds().size()
	var open_card := _card_button(rows[first_card])
	var locked_card := _card_button(rows[rows.size() - 1])
	_check(open_card != null and open_card.visible, "karta rasy startowej ma przycisk zakupu")
	_check(locked_card != null and not locked_card.visible, "karta zablokowanej rasy nie pozwala kupic")

	var hens_before: int = Game.state.hen_count()
	if open_card != null:
		open_card.emit_signal("pressed")
	await _frames(30)
	_check(Game.state.hen_count() == hens_before + 1, "zakup kury dziala")
	_check(_nodes_of_type("FarmChicken").size() == Game.state.hen_count(), "kupiona kura pojawila sie na wybiegu")
	_shot("panel_po_zakupach.png")


## Inkubator: wlozenie jaj, wyklucie pisklecia i jego dorosniecie.
func _test_incubator_panel() -> void:
	var panel: Control = _main.get_node("Hud/Root/BuildingPanel")
	if panel.visible:
		panel.close()
		await _frames(30)
	Game.state.eggs = {"leghorn": Game.eggs_per_chick() * 2}
	var incubator: Node2D = _main.get_node("Farm/Objects/Incubator")
	await _tap(_canvas_point(incubator, Vector2(0, -150)))
	await _frames(30)
	_shot("panel_inkubator.png")

	var actions: VBoxContainer = _main.get_node("Hud/Root/BuildingPanel/Sheet/Content/Scroll/Scrollable/Actions")
	var put: Button = null
	for child in actions.get_children():
		var button := child as Button
		if button != null and button.visible and not button.disabled:
			put = button
			break
	_check(put != null, "inkubator pokazuje przycisk wlozenia jaj")
	if put == null:
		return
	var eggs_before := Game.state.egg_count()
	put.emit_signal("pressed")
	await _frames(20)
	_check(Game.state.incubating.size() == 1, "jaja trafily do inkubatora")
	_check(Game.state.egg_count() < eggs_before, "jaja znikly z magazynu")

	# Przyspieszamy czas, zeby zobaczyc pisklę i dorosla kure na wybiegu.
	var breed_id: String = Game.state.incubating[0].breed_id
	Simulation.advance(Game.state, float(GameData.breed(breed_id).get("incubate_seconds", 0)) + 1.0)
	await _frames(40)
	_check(Game.state.chicks.size() == 1, "pisklę sie wykluło")
	_check(_nodes_of_type("FarmChicken").size() == Game.state.hen_count() + 1,
			"pisklę pojawilo sie na wybiegu")
	_shot("pisklę.png")

	var hens_before: int = Game.state.hen_count()
	Simulation.advance(Game.state, float(GameData.breed(breed_id).get("grow_seconds", 0)) + 1.0)
	await _frames(40)
	_check(Game.state.hen_count() == hens_before + 1, "pisklę wyroslo w kure")
	_check(_nodes_of_type("FarmChicken").size() == Game.state.hen_count(), "wybieg nadazyl za zmiana")


## Sprzedaz kury w sklepie: stado maleje, pieniedzy przybywa, kura znika
## z wybiegu. Handel kurami siedzi teraz w sklepie, razem z jajami i pasza.
func _test_sell_hen() -> void:
	var panel: Control = _main.get_node("Hud/Root/BuildingPanel")
	if panel.visible:
		panel.close()
		await _frames(30)
	var shop: Node2D = _main.get_node("Farm/Objects/Shop")
	await _tap(_canvas_point(shop, Vector2(0, -150)))
	await _frames(30)
	_shot("panel_sklep.png")

	var actions: VBoxContainer = _main.get_node("Hud/Root/BuildingPanel/Sheet/Content/Scroll/Scrollable/Actions")
	# Karta rasy to pionowy box: zdjecie z opisem, potem kup / sprzedaj / mieso.
	var sell_button: Button = null
	for child in actions.get_children():
		var card := child as VBoxContainer
		if card == null:
			continue
		for inner in card.get_children():
			var button := inner as Button
			if button != null and button.visible and not button.disabled \
					and button.text.begins_with(tr("PANEL_SELL_HEN").left(8)):
				sell_button = button
				break
		if sell_button != null:
			break
	_check(sell_button != null, "sklep pokazuje przycisk sprzedazy posiadanej rasy")
	if sell_button == null:
		return
	var hens_before: int = Game.state.hen_count()
	var money_before: float = Game.state.money
	sell_button.emit_signal("pressed")
	await _frames(60)
	_check(Game.state.hen_count() == hens_before - 1, "sprzedaz zmniejsza stado")
	_check(Game.state.money > money_before, "sprzedaz kury daje pieniadze")
	_check(_nodes_of_type("FarmChicken").size() <= Game.state.hen_count(),
			"sprzedana kura znika z wybiegu")


func _test_no_feed_notice() -> void:
	var panel: Control = _main.get_node("Hud/Root/BuildingPanel")
	if panel.visible:
		panel.close()
		await _frames(30)
	var notice: Control = _main.get_node("Hud/Root/Notice")
	Game.state.feed = 0.0
	Game.set_process(true)
	await _frames(10)
	Game.set_process(false)
	_check(notice.visible, "komunikat o braku paszy sie pokazuje")
	_shot("brak_paszy.png")


## Przycisk ukryty w karcie rasy.
## Pierwszy przycisk na karcie rasy — "Kup". Karta jest pionowym boxem:
## u gory zdjecie z opisem, pod nim kup / sprzedaj / mieso.
func _card_button(row: Node) -> Button:
	for child in row.get_children():
		if child is Button:
			return child
		for inner in child.get_children():
			if inner is Button:
				return inner
	return null


# --- narzedzia ----------------------------------------------------------


func _nodes_of_type(class_name_wanted: String) -> Array[Node]:
	var found: Array[Node] = []
	for child in _main.get_node("Farm/Objects").get_children():
		if child.get_script() != null and child.get_script().get_global_name() == class_name_wanted:
			found.append(child)
	return found


func _canvas_point(node: Node2D, offset: Vector2) -> Vector2:
	return node.get_global_transform_with_canvas() * offset


## Dotkniecie w punkcie podanym w pikselach okna. `get_global_transform_with_canvas`
## zwraca juz wspolrzedne okna, wiec nie wolno ich mnozyc po raz drugi przez
## skale — przy oknie innym niz 1080 px szerokosci dotyk ladowal obok celu.
func _tap(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.position = point
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(4)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _shot(file_name: String) -> void:
	get_tree().root.get_texture().get_image().save_png(_out_dir + file_name)


## Okienko "nowa rasa odblokowana": zlota ramka, historia rasy, przycisk.
func _test_unlock_popup() -> void:
	var panel: Control = _main.get_node("Hud/Root/BuildingPanel")
	if panel.visible:
		panel.close()
		await _frames(30)

	var popup: Control = _main.get_node("Hud/Root/UnlockPanel")
	_check(not popup.visible, "okienko rasy jest schowane, dopoki nic sie nie odblokuje")

	# Rasa z konca drabinki, zeby bylo widac i historie, i wysoka cene.
	Events.breed_unlocked.emit("cemani")
	await _frames(45)
	_check(popup.visible, "okienko pokazuje sie po odblokowaniu rasy")
	var lore: Label = popup.get_node("Sheet/Content/Lore")
	var breed_name: Label = popup.get_node("Sheet/Content/Name")
	_check(breed_name.text == tr(GameData.breed("cemani").get("name", "")), "nazwa rasy w naglowku")
	_check(lore.text.length() > 80, "historia rasy jest wypelniona")
	_check(not lore.text.begins_with("BREED_"), "historia ma tlumaczenie, a nie goly klucz")
	_check((popup.get_node("Sheet/Content/Frame/Portrait") as TextureRect).texture != null,
			"portret rasy jest ustawiony")
	_shot("okienko_rasy.png")

	# Druga rasa czeka w kolejce i pokazuje sie po zamknieciu pierwszej.
	Events.breed_unlocked.emit("dongtao")
	await _frames(10)
	_check(breed_name.text == tr(GameData.breed("cemani").get("name", "")),
			"druga rasa czeka, nie podmienia pierwszej")
	(popup.get_node("Sheet/Content/Close") as Button).emit_signal("pressed")
	await _frames(60)
	_check(popup.visible, "po zamknieciu pokazuje sie kolejna rasa z kolejki")
	_check(breed_name.text == tr(GameData.breed("dongtao").get("name", "")), "teraz druga rasa")
	(popup.get_node("Sheet/Content/Close") as Button).emit_signal("pressed")
	await _frames(60)
	_check(not popup.visible, "po pustej kolejce okienko sie chowa")


## Przejecie farmy po kodzie przepisanym z innego urzadzenia.
##
## Uruchamia sie tylko przeciwko atrapie serwera na localhost — nie chcemy,
## zeby test dymny pukal do prawdziwej bazy gracza.
func _test_farm_code_restore() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/backend.json"))
	var config: Dictionary = parsed if parsed is Dictionary else {}
	var url := String(config.get("url", ""))
	if not Cloud.is_enabled() or not url.begins_with("http://localhost"):
		return

	const CODE := "ABCD-EFGH-2345"
	const MONEY := 777777.0
	var own_code := Cloud.player_id
	_check(own_code != CODE, "wlasny kod rozni sie od przepisywanego")

	# Zly kod ma zostac odrzucony, zanim cokolwiek poleci do serwera.
	_check(not Game.restore_from_code("za krotki"), "niepoprawny kod odrzucony")
	_check(Cloud.player_id == own_code, "po zlym kodzie farma sie nie zmienia")
	_check(not Game.restore_from_code(own_code), "wlasny kod nie ma czego wczytywac")

	# Farma z serwera wygrywa, chociaz lokalny zapis jest swiezszy.
	Game.state.money = 1.0
	Game.save()
	await _frames(10)
	_check(Game.restore_from_code("abcd efgh 2345"), "kod przyjety mimo malych liter i spacji")
	_check(Cloud.player_id == CODE, "kod farmy przestawiony")
	await _frames(240)
	_check(is_equal_approx(Game.state.money, MONEY),
			"wczytano farme z serwera (konto %.0f zl)" % Game.state.money)
	_check(Game.state.hen_count() > 0, "stado przyszlo razem z zapisem")

	# Po przejeciu farmy zapis lokalny ma juz nowy stan.
	var local := SaveGame.load_state()
	_check(not local.is_empty() and is_equal_approx((local["state"] as FarmState).money, MONEY),
			"przejeta farma zapisala sie lokalnie")

	Cloud.set_player_id(own_code)
	SaveGame.clear()
	Game.new_game()


## Ekran powitalny na swiezym urzadzeniu: nowa farma, kod i wejscie do gry.
func _test_start_screen() -> void:
	var start: Control = _main.get_node("Hud/Root/StartPanel")
	await _frames(30)
	_check(start.visible, "ekran powitalny pokazuje sie na swiezym urzadzeniu")
	_check(not Game.is_processing(), "gospodarstwo stoi, dopoki gracz nie zacznie")
	var choice: Control = start.get_node("Sheet/Content/Choice")
	var created: Control = start.get_node("Sheet/Content/Created")
	_check(choice.visible and not created.visible, "najpierw wybor: nowa farma albo kod")
	_shot("ekran_startowy.png")

	(start.get_node("Sheet/Content/Choice/NewFarm") as Button).emit_signal("pressed")
	await _frames(20)
	_check(created.visible and not choice.visible, "po zalozeniu farmy pokazuje sie kod")
	var code: String = (start.get_node("Sheet/Content/Created/Code") as Label).text
	_check(Cloud.is_short_code(code), "kod farmy to szesc cyfr (jest '%s')" % code)
	_check(code == Cloud.player_id, "pokazany kod to kod tej farmy")
	_shot("ekran_kod.png")

	(start.get_node("Sheet/Content/Created/Play") as Button).emit_signal("pressed")
	await _frames(40)
	_check(not start.visible, "po nacisnieciu Zaczynamy ekran znika")
	_check(Game.is_processing(), "gospodarstwo rusza")
	_check(not Game.is_new_player, "gra nie uznaje juz gracza za nowego")

	# Po zamknieciu ekranu symulacje zatrzymujemy, jak reszta testu tego oczekuje.
	Game.set_process(false)
