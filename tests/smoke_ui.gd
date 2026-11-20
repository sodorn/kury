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
	await _test_sick_and_fox_look()

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
	# Scena dokleja jajka przy swoim cyklicznym odswiezeniu, a nie od razu po
	# sygnale — czekamy, az dojdzie do dwoch, zamiast zgadywac liczbe klatek.
	var eggs := await _wait_for_nodes("GroundEgg", 2)
	_check(eggs.size() == 2, "jajka pojawily sie na wybiegu (jest %d)" % eggs.size())
	_shot("jajka.png")
	if eggs.is_empty():
		return
	# Jedno dotkniecie zgarnia wszystko w promieniu `run.pickup_radius`.
	# Ustawiamy jajka tak, zeby jedno bylo w zasiegu, a drugie daleko poza nim.
	var radius := float(GameData.balance().get("run", {}).get("pickup_radius", 300.0))
	var first := eggs[0] as Node2D
	var second := eggs[1] as Node2D
	second.position = first.position + Vector2(0.0, radius * 0.5)
	var far := eggs[2] as Node2D if eggs.size() > 2 else null
	var stored_before := Game.state.egg_count()
	await _tap(_canvas_point(first, Vector2(0, -38)))
	await _frames(40)
	_check(Game.state.egg_count() == stored_before + 2,
			"jedno dotkniecie zgarnia jajka z calego poblizu (+%d)" % [
				Game.state.egg_count() - stored_before])
	var left := await _wait_for_nodes("GroundEgg", 0)
	_check(left.is_empty(), "zebrane jajka znikaja z wybiegu (zostalo %d)" % left.size())

	# Jajko poza promieniem ma zostac na miejscu.
	Game.state.eggs_on_ground.append("leghorn")
	Game.state.eggs_on_ground.append("leghorn")
	Events.eggs_laid.emit(2)
	var pair := await _wait_for_nodes("GroundEgg", 2)
	if pair.size() == 2:
		var near := pair[0] as Node2D
		var away := pair[1] as Node2D
		away.position = near.position + Vector2(radius * 2.0, 0.0)
		var before_far := Game.state.egg_count()
		await _tap(_canvas_point(near, Vector2(0, -38)))
		await _frames(40)
		_check(Game.state.egg_count() == before_far + 1,
				"jajko poza promieniem zostaje na wybiegu")
		var rest := await _wait_for_nodes("GroundEgg", 1)
		_check(rest.size() == 1, "i dalej tam lezy (jest %d)" % rest.size())
		for node in rest:
			(node as GroundEgg).collect()
		await _frames(30)


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

	# Kazda rasa ma teraz widoczny przycisk zakupu — sklep nie ma blokad.
	var first_card := rows.size() - GameData.breeds().size()
	var open_card := _card_button(rows[first_card])
	var last_card := _card_button(rows[rows.size() - 1])
	_check(open_card != null and open_card.visible, "karta rasy startowej ma przycisk zakupu")
	_check(last_card != null and last_card.visible, "najdrozsza rasa tez ma przycisk zakupu")
	_check(last_card != null and last_card.disabled, "ale bez pieniedzy przycisk jest wyszarzony")

	var hens_before: int = Game.state.hen_count()
	if open_card != null:
		open_card.emit_signal("pressed")
	await _frames(30)
	await _dismiss_unlock_popup()
	_check(Game.state.hen_count() == hens_before + 1, "zakup kury dziala")
	_check(_nodes_of_type("FarmChicken").size() == Game.state.hen_count(), "kupiona kura pojawila sie na wybiegu")
	_shot("panel_po_zakupach.png")

	# Kogut: kupiony przez sklep ma stanac na wybiegu z wlasna grafika.
	var cocks_before := Game.state.rooster_count()
	Game.state.money = 100000.0
	_check(Game.buy_hen("rhode", true), "sklep sprzedaje koguta")
	_check(Game.state.rooster_count() == cocks_before + 1, "kogut doliczony do stada")
	# Pierwsza sztuka rasy rhode, wiec wyskakuje okienko z jej historia —
	# dopoki stoi otwarte, blokuje dotkniecia kolejnych budynkow.
	await _frames(30)
	await _dismiss_unlock_popup()
	var cocks := await _wait_for_nodes("FarmChicken", Game.state.hen_count())
	var rooster_nodes := 0
	for node in cocks:
		if (node as FarmChicken).is_rooster:
			rooster_nodes += 1
	_check(rooster_nodes == Game.state.rooster_count(), "koguty stoja na wybiegu (jest %d)" % rooster_nodes)
	# Zdjecie samego wybiegu, bez panelu sklepu na wierzchu.
	var shop_panel: Control = _main.get_node("Hud/Root/BuildingPanel")
	if shop_panel.visible:
		shop_panel.close()
		await _frames(30)
	_shot("wybieg_z_kogutem.png")


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
	var with_chick := await _wait_for_nodes("FarmChicken", Game.state.hen_count() + 1)
	_check(with_chick.size() == Game.state.hen_count() + 1,
			"pisklę pojawilo sie na wybiegu")
	_shot("pisklę.png")

	var hens_before: int = Game.state.hen_count()
	Simulation.advance(Game.state, float(GameData.breed(breed_id).get("grow_seconds", 0)) + 1.0)
	await _frames(40)
	_check(Game.state.hen_count() == hens_before + 1, "pisklę wyroslo w kure")
	var grown := await _wait_for_nodes("FarmChicken", Game.state.hen_count())
	_check(grown.size() == Game.state.hen_count(), "wybieg nadazyl za zmiana")


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
	# Pusty magazyn zatrzymuje cale gospodarstwo, wiec melduje sie okienkiem,
	# a nie znikajacym paskiem.
	var alert: Control = _main.get_node("Hud/Root/AlertPanel")
	Game.state.feed = 0.0
	Game.set_process(true)
	await _frames(10)
	Game.set_process(false)
	await _frames(30)
	_check(alert.visible, "brak paszy melduje sie okienkiem")
	_shot("brak_paszy.png")
	var ok_button := _find_button(alert)
	if ok_button != null:
		ok_button.emit_signal("pressed")
		await _frames(40)
	# Magazyn trzeba uzupelnic, inaczej kolejne testy dostana to okienko
	# w najmniej spodziewanym momencie.
	Game.state.feed = 100000.0


## Pierwszy przycisk w poddrzewie — okienka maja ich po jednym.
func _find_button(root: Node) -> Button:
	for child in root.get_children():
		if child is Button:
			return child
		var deeper := _find_button(child)
		if deeper != null:
			return deeper
	return null


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


## Czeka, az w scenie pojawi sie zadana liczba wezlow danego typu. Zwraca to,
## co zastanie po ostatniej probie, zeby test mogl sam powiedziec, czego brakuje.
func _wait_for_nodes(class_name_wanted: String, wanted: int, tries: int = 12) -> Array[Node]:
	var found := _nodes_of_type(class_name_wanted)
	for i in tries:
		if found.size() == wanted:
			break
		await _frames(10)
		found = _nodes_of_type(class_name_wanted)
	return found


func _canvas_point(node: Node2D, offset: Vector2) -> Vector2:
	return node.get_global_transform_with_canvas() * offset


## Dotkniecie w punkcie podanym we wspolrzednych widoku (1080x1920) — tak jak
## zwraca je `_canvas_point`. `Input.parse_input_event` udaje zdarzenie z systemu,
## a system podaje piksele OKNA, ktore przy `window_width_override=486` sa 0,45
## raza mniejsze. Bez przeliczenia przez `get_screen_transform` dotkniecie ladowalo
## ponad dwa razy dalej niz cel i zaden budynek sie nie otwieral.
func _tap(viewport_point: Vector2) -> void:
	var point := get_viewport().get_screen_transform() * viewport_point
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
	await _dismiss_unlock_popup()
	_check(not popup.visible, "okienko rasy jest schowane, dopoki nic sie nie pojawi")

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
	await get_tree().create_timer(3.0).timeout
	_check(is_equal_approx(Game.state.money, MONEY),
			"wczytano farme z serwera (konto %.0f zl)" % Game.state.money)
	_check(Game.state.hen_count() > 0, "stado przyszlo razem z zapisem")

	# Po przejeciu farmy zapis lokalny ma juz nowy stan.
	var local := SaveGame.load_state()
	_check(not local.is_empty() and is_equal_approx((local["state"] as FarmState).money, MONEY),
			"przejeta farma zapisala sie lokalnie")

	# --- wyscig, przez ktory wczytywanie farmy nie dzialalo ---------------
	# 1. Autozapis w trakcie czekania na odpowiedz. Kod farmy jest juz
	#    przestawiony, wiec push wrzucilby nasz lokalny stan na cudze miejsce
	#    i skasowal farme, po ktora gracz wlasnie siegnal.
	Cloud.set_player_id(own_code)
	SaveGame.clear()
	Game.new_game()
	Game.state.money = 1.0
	await _frames(10)
	_check(Game.restore_from_code(CODE), "kod przyjety po raz drugi")
	Game.save()                      # tak jak zrobilby autozapis
	await get_tree().create_timer(3.0).timeout
	_check(is_equal_approx(Game.state.money, MONEY),
			"autozapis nie przykryl cudzej farmy (konto %.0f zl)" % Game.state.money)

	# 2. Startowe pobranie w locie, a gracz wpisuje kod. Spozniona odpowiedz
	#    nie moze ani skasowac oczekiwania, ani podmienic stanu.
	Cloud.set_player_id(own_code)
	SaveGame.clear()
	Game.new_game()
	Game.state.money = 2.0
	Game.save()
	await _frames(10)
	Cloud.pull()                     # zapytanie o wlasna farme, jeszcze w locie
	_check(Game.restore_from_code(CODE), "kod przyjety mimo trwajacego zapytania")
	await get_tree().create_timer(3.0).timeout
	_check(is_equal_approx(Game.state.money, MONEY),
			"farma wczytana mimo wyscigu z pobraniem startowym (konto %.0f zl)" % Game.state.money)

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


## Zamyka okienko z historia rasy, jesli wlasnie wyskoczylo. Po zmianie
## z wersji 9.0 pokazuje sie przy pierwszym zakupie kazdej rasy i — jako
## okno modalne — przykrywa sklep.
func _dismiss_unlock_popup() -> void:
	var popup: Control = _main.get_node("Hud/Root/UnlockPanel")
	while popup.visible:
		(popup.get_node("Sheet/Content/Close") as Button).emit_signal("pressed")
		await _frames(40)


## Oprawa choroby i lisa: zgnilozielona kura z mgielka, okienko ostrzezenia
## i chmura piór po napasci.
func _test_sick_and_fox_look() -> void:
	var panel: Control = _main.get_node("Hud/Root/BuildingPanel")
	if panel.visible:
		panel.close()
		await _frames(30)

	# Chora kura: zielen, przechylenie i mgla zamiast dawnej ikonki.
	Game.state.chickens.clear()
	for i in 6:
		Game.state.chickens.append(Chicken.create("leghorn"))
	Game.state.chickens[0].sick = true
	Game.state.chickens[1].sick = true
	await _frames(80)
	var sick_nodes := 0
	var mist_on := 0
	for node in _nodes_of_type("FarmChicken"):
		var animal := node as FarmChicken
		if not animal.is_sick:
			continue
		sick_nodes += 1
		if (animal.get_node("Mist") as CPUParticles2D).emitting:
			mist_on += 1
	_check(sick_nodes == 2, "obie chore kury widac na wybiegu")
	_check(mist_on == sick_nodes, "od kazdej chorej kury idzie mgielka")
	_check(_main.get_node_or_null("Hud/Root/UnlockPanel") != null, "okienko rasy nadal w scenie")
	_shot("chore_kury.png")

	# Okienko ostrzezenia o chorobie.
	var alert: Control = _main.get_node("Hud/Root/AlertPanel")
	_check(not alert.visible, "ostrzezenie schowane, dopoki nic sie nie dzieje")
	Events.alert.emit(tr("ALERT_SICK_TITLE"), tr("ALERT_SICK_BODY") % 2)
	await _frames(40)
	_check(alert.visible, "ostrzezenie o chorobie pokazuje sie jako okienko")
	_check((alert.get_node("Sheet/Content/Title") as Label).text == tr("ALERT_SICK_TITLE"),
			"naglowek ostrzezenia")
	_shot("okienko_choroba.png")
	(alert.get_node("Sheet/Content/Close") as Button).emit_signal("pressed")
	await _frames(40)
	_check(not alert.visible, "ostrzezenie da sie zamknac")

	# Lis: wejscie, komunikat i chmura piór przy napasci.
	Events.fox_arrived.emit(3, 7.0)
	await _frames(60)
	var foxes := _nodes_of_type("FarmFox")
	_check(foxes.size() == 1, "lis wszedl na wybieg")
	_shot("lis_na_wybiegu.png")
	Events.fox_visited.emit(3)
	await _frames(20)
	var feathers_on := false
	var blood_on := false
	for node in foxes:
		feathers_on = feathers_on or (node.get_node("Feathers") as CPUParticles2D).emitting
		blood_on = blood_on or (node.get_node("Blood") as CPUParticles2D).emitting
	_check(feathers_on, "po napasci leca piora")
	_check(blood_on, "po napasci leci krew")
	# Plamy krwi zostaja na wybiegu, wiec sa dziecmi kontenera, nie lisa.
	var splats := 0
	for child in _main.get_node("Farm/Objects").get_children():
		var sprite := child as Sprite2D
		if sprite != null and sprite.texture != null \
				and sprite.texture.resource_path.ends_with("blood_splat.svg"):
			splats += 1
	_check(splats > 0, "na wybiegu zostaly plamy krwi (jest %d)" % splats)
	_shot("lis_piora.png")
	await _frames(90)
	_check(_nodes_of_type("FarmFox").is_empty(), "lis odszedl z wybiegu")
	_shot("lis_krew.png")

	# Lis zawrocony przez plot: ma przebiec i zniknac, nic nie zabierajac.
	var flock_before := Game.state.hen_count()
	Events.fox_repelled.emit()
	await _frames(20)
	var repelled := _nodes_of_type("FarmFox")
	_check(repelled.size() == 1, "zawrocony lis pokazuje sie na wybiegu")
	_check(not (repelled[0] as FarmFox).input_pickable,
			"zawroconego lisa nie da sie przeganiac, bo juz odchodzi")
	_shot("lis_zawrocony.png")
	await _frames(240)
	_check(_nodes_of_type("FarmFox").is_empty(), "zawrocony lis sam znika z wybiegu")
	_check(Game.state.hen_count() == flock_before, "zawrocony lis nic nie zabral")
