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
	# Testy NIGDY na prawdziwy serwer (patrz Cloud.use_test_server). Wyjatek:
	# backend.json wskazuje lokalny udawany serwer - wtedy zostawiamy go.
	if not Cloud.is_test_server():
		Cloud.use_test_server()
	_check(Cloud.is_test_server(), "test dymny nie rozmawia z baza graczy")
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
	await _test_fox_lurk_and_fence()
	await _test_feed_panels()
	await _test_upgrade_looks()
	await _test_dog_breeds()
	await _test_fox_death()

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
		if id == "coop":
			await _check_dog_offer(panel)
		if id == "incubator":
			await _check_incubator_upgrade(panel)
		await _tap(Vector2(540, 260))
		await _frames(30)
		_check(not panel.visible, "panel '%s' zamyka sie dotknieciem tla" % id)



## Pies ma byc do kupienia OD RAZU, bez plotu jako warunku, i ma stac przed
## plotem, bo jest tanszy. Wlasciciel szukal go w panelu i nie znalazl —
## test pilnuje, zeby przycisk nie zniknal po jakiejs przyszlej przebudowie.
func _check_dog_offer(panel: Control) -> void:
	await _frames(20)
	var rows: VBoxContainer = panel.get_node(
			"Sheet/Content/Scroll/Gutter/Scrollable/Rows")
	var actions: VBoxContainer = panel.get_node(
			"Sheet/Content/Scroll/Gutter/Scrollable/Actions")
	var stany := "\n".join(_labels_in(rows))
	_check(stany.contains(tr("PANEL_FOX_FENCE")), "kurnik pokazuje stan plotu")
	_check(stany.contains(tr("PANEL_FOX_DOG")), "kurnik pokazuje stan psa")

	var pies := -1
	var plot := -1
	var teksty: Array[String] = []
	var index := 0
	for node in _controls_of_type(actions, "Button"):
		var button := node as Button
		if not button.visible:
			continue
		teksty.append(button.text)
		if button.text.contains(tr("DOG_BUY_MUTT")) and pies < 0:
			pies = index
		if button.text.contains(tr("GUARD_BUY_FENCE")) and plot < 0:
			plot = index
		index += 1
	_check(pies >= 0, "jest przycisk zakupu psa: %s" % "; ".join(teksty))
	_check(plot >= 0, "jest przycisk zakupu plotu")
	if pies >= 0 and plot >= 0:
		_check(pies < plot, "pies stoi przed plotem (tanszy)")
	# Szukamy NIEPODSTAWIONYCH wzorcow, a nie samego znaku procenta — napis
	# o plocie slusznie zawiera "60%".
	for tekst in teksty:
		var czysty := tekst.contains("%s") or tekst.contains("%d")
		_check(not czysty, "przycisk ma podstawione wszystkie wartosci: %s" % tekst)


## Wlasciciel zglosil, ze przycisk rozbudowy inkubatora jest "caly czas
## wyszarzony". Sprawdzamy to wprost: z pusta kiesznia ma byc wyszarzony,
## a po dosypaniu pieniedzy — klikalny.
func _check_incubator_upgrade(panel: Control) -> void:
	var actions: VBoxContainer = panel.get_node(
			"Sheet/Content/Scroll/Gutter/Scrollable/Actions")
	var cena := float(Game.state.next_incubator_upgrade().get("price", 0))
	_check(cena > 0.0, "jest co kupowac w inkubatorze (%.0f zl)" % cena)

	var przycisk: Button = null
	for node in _controls_of_type(actions, "Button"):
		var b := node as Button
		if b.visible and b.text.contains(tr("PANEL_UPGRADE_INCUBATOR").split(":")[0]):
			przycisk = b
	_check(przycisk != null, "jest przycisk rozbudowy inkubatora")
	if przycisk == null:
		return

	var kasa := Game.state.money
	Game.state.money = cena - 1.0
	await _frames(20)
	_check(przycisk.disabled, "bez pieniedzy przycisk jest wyszarzony")
	_check(przycisk.text.contains(tr("PANEL_MISSING_MONEY").split(" ")[0]),
			"wyszarzony przycisk mowi, ze brakuje pieniedzy")
	# Dopisek nie moze sie mnozyc przy kolejnych odswiezeniach.
	var raz := przycisk.text
	await _frames(40)
	_check(przycisk.text == raz,
			"napis nie rosnie przy kazdym odswiezeniu (%s)" % przycisk.text)

	Game.state.money = cena + 10.0
	await _frames(20)
	_check(not przycisk.disabled,
			"z pieniedzmi przycisk da sie kliknac (tekst: %s)" % przycisk.text)

	var poziom := Game.state.incubator_level
	przycisk.emit_signal("pressed")
	await _frames(20)
	_check(Game.state.incubator_level == poziom + 1,
			"klikniecie faktycznie rozbudowuje inkubator (%d -> %d)"
			% [poziom, Game.state.incubator_level])
	Game.state.money = kasa


## Widoczny przycisk o danym napisie, gdziekolwiek w interfejsie.
func _button_labelled(label: String) -> Button:
	for node in _controls_of_type(_main, "Button"):
		var button := node as Button
		if button.visible and button.is_visible_in_tree() and button.text == label:
			return button
	return null


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
	var actions: VBoxContainer = _main.get_node("Hud/Root/BuildingPanel/Sheet/Content/Scroll/Gutter/Scrollable/Actions")
	var rows := actions.get_children()
	# 12.18: doszedl przycisk "kup 10 workow paszy".
	_check(rows.size() == 6 + GameData.breeds().size(),
			"sklep ma przyciski, notke i karte kazdej rasy (jest %d)" % rows.size())
	if rows.size() < 3:
		return

	# Jaja schodza partiami po 100, a resztka ponizej setki tez.
	Game.state.eggs.clear()
	Game.state.egg_ages.clear()
	Game.state.add_egg("leghorn", 150)
	await _frames(20)
	var sprzedaz := rows[0] as Button
	_check(sprzedaz.text.begins_with("Sprzedaj 100 jaj za"),
			"przycisk sprzedaje setke (jest '%s')" % sprzedaz.text)
	var money_before: float = Game.state.money
	sprzedaz.emit_signal("pressed")
	await _frames(20)
	_check(Game.state.egg_count() == 50 and Game.state.money > money_before,
			"po sprzedazy setki zostaje 50 jaj (jest %d)" % Game.state.egg_count())
	_check(sprzedaz.text.begins_with("Sprzedaj 50 jaj za"), "potem przycisk sprzedaje resztke")
	sprzedaz.emit_signal("pressed")
	await _frames(10)
	_check(Game.state.egg_count() == 0, "sprzedaz jaj dziala do konca")
	_check(sprzedaz.disabled, "bez jaj przycisk jest wyszarzony")
	var pasza_btn := rows[1] as Button
	_check(pasza_btn.text.begins_with("Kup worek paszy"),
			"przycisk paszy: 'Kup worek paszy ...' (jest '%s')" % pasza_btn.text)

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
	_check(open_card != null and open_card.text.begins_with("Kup kurę za"),
			"przycisk mowi 'Kup kurę za ...' (jest '%s')" % (open_card.text if open_card else ""))
	if open_card != null:
		open_card.emit_signal("pressed")
	await _frames(20)
	# Kupno idzie przez potwierdzenie (wlasciciel, 24.11).
	_check(Game.state.hen_count() == hens_before, "samo klikniecie jeszcze nie kupuje")
	var tak_kup := _button_labelled(tr("CONFIRM_YES_BUY"))
	var nie_kup := _button_labelled(tr("CONFIRM_NO"))
	_check(tak_kup != null and nie_kup != null, "pojawilo sie pytanie o kupno")
	var ekran := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	if tak_kup != null:
		_check(ekran.encloses(tak_kup.get_global_rect()), "'Tak, kup' miesci sie na ekranie")
	_shot("pytanie_kupno.png")
	if nie_kup != null:
		nie_kup.emit_signal("pressed")
	await _frames(20)
	_check(Game.state.hen_count() == hens_before, "'Nie' niczego nie kupuje")
	if open_card != null:
		open_card.emit_signal("pressed")
	await _frames(20)
	tak_kup = _button_labelled(tr("CONFIRM_YES_BUY"))
	if tak_kup != null:
		tak_kup.emit_signal("pressed")
	await _frames(30)
	await _dismiss_unlock_popup()
	_check(Game.state.hen_count() == hens_before + 1, "zakup kury dziala po potwierdzeniu")
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

	var actions: VBoxContainer = _main.get_node("Hud/Root/BuildingPanel/Sheet/Content/Scroll/Gutter/Scrollable/Actions")
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

	# Koledzy zglosili, ze pasek postepu byl goly: nie bylo ani procentow,
	# ani czasu. Szukamy ich w panelu po wlozeniu jaj.
	await _frames(20)
	# Wiersze stanu zostaly w Rows, paski postepu przeniosly sie do Bars pod
	# przyciskami — zagladamy w oba miejsca.
	var rows: VBoxContainer = _main.get_node(
			"Hud/Root/BuildingPanel/Sheet/Content/Scroll/Gutter/Scrollable/Rows")
	var bars: VBoxContainer = _main.get_node(
			"Hud/Root/BuildingPanel/Sheet/Content/Scroll/Gutter/Scrollable/Bars")
	var texts := _labels_in(rows)
	texts.append_array(_labels_in(bars))
	var joined := "\n".join(texts)
	_check(joined.contains("%"), "pasek inkubatora podaje procent postepu")
	_check(joined.contains(tr("PANEL_INCUBATOR_GROUP")),
			"paski maja naglowek grupy '%s'" % tr("PANEL_INCUBATOR_GROUP"))
	_check(joined.contains(tr("PANEL_LEVEL")), "panel pokazuje poziom inkubatora")
	# Swieza partia stoi na zerze, i tak ma byc. Puszczamy czwiartke czasu
	# wykluwania, zeby zobaczyc, czy pasek faktycznie rusza.
	var quarter := float(GameData.breed("leghorn").get("incubate_seconds", 0.0)) * 0.25
	Simulation.advance(Game.state, quarter)
	await _frames(30)
	var has_bar := false
	for bar in _controls_of_type(bars, "ProgressBar"):
		if (bar as ProgressBar).visible and (bar as ProgressBar).value > 0.0:
			has_bar = true
	_check(has_bar, "pasek postepu wypelnia sie, a nie stoi na zerze")
	var moved := "\n".join(_labels_in(bars))
	_check(not moved.contains("0%"), "po cwiartce czasu nie pisze juz 0 procent")
	_shot("panel_inkubator_postep.png")

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


## Wszystkie napisy z etykiet w galezi — do sprawdzania, co panel naprawde
## pokazuje, bez zgadywania sciezek do kazdego wiersza osobno.
func _labels_in(root: Node) -> Array[String]:
	var found: Array[String] = []
	for node in _controls_of_type(root, "Label"):
		var label := node as Label
		if label.visible and not label.text.is_empty():
			found.append(label.text)
	return found


func _controls_of_type(root: Node, type_name: String) -> Array[Node]:
	var found: Array[Node] = []
	if root.is_class(type_name):
		found.append(root)
	for child in root.get_children():
		found.append_array(_controls_of_type(child, type_name))
	return found


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

	var actions: VBoxContainer = _main.get_node("Hud/Root/BuildingPanel/Sheet/Content/Scroll/Gutter/Scrollable/Actions")
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
	await _frames(30)
	# Sprzedaz ptaka idzie teraz przez potwierdzenie: jedno nieuwazne
	# dotkniecie nie moze kosztowac wyhodowanej kury.
	_check(Game.state.hen_count() == hens_before,
			"samo klikniecie jeszcze nic nie sprzedaje")
	var tak := _button_labelled(tr("CONFIRM_YES"))
	var nie := _button_labelled(tr("CONFIRM_NO"))
	_check(tak != null and nie != null, "pojawilo sie pytanie z dwoma odpowiedziami")
	if tak == null:
		return

	# Okienko ma byc CALE na ekranie. Wczesniej test sprawdzal tylko, czy
	# przyciski istnieja — a one istnialy, tylko polowa wystawala za prawa
	# krawedz telefonu. Wlasciciel zobaczyl to na zrzucie, test nie.
	var ekran := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	for przycisk: Button in [tak, nie]:
		var r := przycisk.get_global_rect()
		_check(ekran.encloses(r),
				"przycisk '%s' miesci sie na ekranie (%s w %s)" % [przycisk.text, r, ekran])
	var pytanie: Label = null
	var w_gore: Node = tak.get_parent()
	while w_gore != null and pytanie == null:
		for dziecko in w_gore.get_children():
			if dziecko is Label:
				pytanie = dziecko
		w_gore = w_gore.get_parent()
	_check(pytanie != null and ekran.encloses(pytanie.get_global_rect()),
			"tekst pytania miesci sie na ekranie")
	var srodek_okna := (tak.get_global_rect().merge(nie.get_global_rect())).get_center().x
	_check(absf(srodek_okna - ekran.size.x * 0.5) < ekran.size.x * 0.1,
			"okienko stoi na srodku ekranu (%.0f vs %.0f)" % [srodek_okna, ekran.size.x * 0.5])
	_shot("pytanie_sprzedaz.png")

	# Najpierw sprawdzamy, ze "Nie" naprawde nic nie robi.
	nie.emit_signal("pressed")
	await _frames(20)
	_check(Game.state.hen_count() == hens_before, "'Nie' zostawia kure w spokoju")
	_check(_button_labelled(tr("CONFIRM_YES")) == null, "pytanie znika po odpowiedzi")

	sell_button.emit_signal("pressed")
	await _frames(30)
	tak = _button_labelled(tr("CONFIRM_YES"))
	_check(tak != null, "pytanie wraca przy kolejnej probie")
	if tak == null:
		return
	tak.emit_signal("pressed")
	# Wybieg dogania stan stada dopiero przy nastepnym przegladzie, a doszlo
	# jedno dodatkowe klikniecie (potwierdzenie) — dajemy mu wiecej czasu.
	await _seconds(2.0)
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


## Klawisz klawiatury kodu o danym napisie.
func _keypad_key(keypad: Node, label: String) -> Button:
	for child in keypad.get_children():
		for inner in child.get_children():
			var key := inner as Button
			if key != null and key.text == label:
				return key
	return null


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


## Czeka ZEGARKIEM, nie klatkami. Animacje lisa trwaja 0,6 s i 2,7 s
## realnego czasu, a liczba klatek na sekunde zalezy od obciazenia maszyny:
## na szybszym przebiegu 240 klatek mijalo w pol sekundy i test wywalal sie
## na tym, ze lis "nie znikl", choc jego animacja dopiero sie zaczela.
func _seconds(duration: float) -> void:
	var until := Time.get_ticks_msec() + int(duration * 1000.0)
	while Time.get_ticks_msec() < until:
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

	# Klawiatura numeryczna w grze. Pole tekstowe Godota nie wpuszczalo cyfr
	# na telefonie, wiec kod wpisuje sie wlasnymi przyciskami — i to one
	# musza dzialac, a nie klawiatura systemowa.
	var keypad: CodeKeypad = start.get_node("Sheet/Content/Choice/CodeRow/Keypad")
	_check(keypad != null and keypad.visible, "klawiatura kodu jest na ekranie")
	if keypad != null:
		for digit in ["7", "5", "6", "3", "6", "2"]:
			var key := _keypad_key(keypad, digit)
			_check(key != null, "klawisz %s istnieje" % digit)
			if key != null:
				key.emit_signal("pressed")
		await _frames(5)
		_check(keypad.code() == "756362", "cyfry wchodza do kodu (jest '%s')" % keypad.code())
		var ok := _keypad_key(keypad, tr("CODE_OK"))
		_check(ok != null and not ok.disabled, "przy komplecie cyfr zatwierdzenie jest aktywne")
		var back := _keypad_key(keypad, tr("CODE_BACK"))
		if back != null:
			back.emit_signal("pressed")
			await _frames(5)
		_check(keypad.code() == "75636", "kasowanie zabiera ostatnia cyfre")
		# Wiecej cyfr niz miesci kod ma byc zignorowane.
		for digit in ["1", "9"]:
			var key := _keypad_key(keypad, digit)
			if key != null:
				key.emit_signal("pressed")
		await _frames(5)
		_check(keypad.code() == "756361", "kod nie rosnie ponad szesc cyfr (jest '%s')" % keypad.code())
		_shot("klawiatura_kodu.png")

		# Odpowiedz serwera musi byc widoczna W OKIENKU. Pasek z komunikatem
		# lezy w drzewie przed ekranem powitalnym i jest przez niego zaslaniany,
		# wiec gracz wpisywal kod i nie widzial zupelnie nic.
		var status: Label = start.get_node("Sheet/Content/Choice/CodeRow/Status")
		_check(not status.visible, "dopoki nic sie nie dzieje, miejsce na komunikat jest puste")
		(start.get_node("Sheet/Content/Choice/CodeRow/Load") as Button).emit_signal("pressed")
		await _frames(5)
		_check(status.visible and not status.text.is_empty(),
				"po nacisnieciu wczytywania okienko od razu cos mowi")
		# Czekamy na odpowiedz albo na uplyniecie czasu zapytania.
		for i in 60:
			if not (start.get_node("Sheet/Content/Choice/CodeRow/Load") as Button).disabled:
				break
			await _frames(10)
		_check(status.visible and not status.text.is_empty(),
				"wynik proby widac w okienku: '%s'" % status.text)
		keypad.clear()
		await _frames(5)
		_check(keypad.code().is_empty(), "czyszczenie kasuje caly kod")

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

	# Lis: wejscie, komunikat i chmura piór przy napasci. Stan gry musi
	# mowic, ze wizyta trwa - od 12.18 lis sam sprawdza fox_visit_left
	# i wychodzi, gdy wizyta w grze sie skonczyla.
	Game.state.fox_visit_left = 7.0
	Game.state.fox_taps_left = 20
	Events.fox_arrived.emit(3, 7.0)
	await _seconds(1.0)
	var foxes := _nodes_of_type("FarmFox")
	_check(foxes.size() == 1, "lis wszedl na wybieg")
	# Drugi sygnal przyjscia NIE moze dolozyc drugiego lisa. Wlasciciel
	# skonczyl z trzema naraz, ktore nie odchodzily.
	Events.fox_arrived.emit(3, 7.0)
	Events.fox_arrived.emit(3, 7.0)
	await _frames(20)
	_check(_nodes_of_type("FarmFox").size() == 1, "na wybiegu jest najwyzej JEDEN lis")
	_shot("lis_na_wybiegu.png")
	Events.fox_visited.emit(3)
	Events.fox_victims.emit(["leghorn", "marans", "cemani"])
	await _frames(20)
	var feathers_on := false
	var blood_on := false
	for node in foxes:
		feathers_on = feathers_on or (node.get_node("Feathers") as CPUParticles2D).emitting
		blood_on = blood_on or (node.get_node("Blood") as CPUParticles2D).emitting
	_check(feathers_on, "po napasci leca piora")
	# Piora w kolorze ofiar: jedna fontanna na kure, barwy z breeds.json.
	var fontanny := 0
	var ciemne := false
	for node in foxes:
		for child in (node as Node).get_children():
			var p := child as CPUParticles2D
			if p == null or p.texture == null or not p.texture.resource_path.ends_with("feather.svg"):
				continue
			if p.emitting and p.color_initial_ramp != null:
				fontanny += 1
				if p.color_initial_ramp.get_color(0).v < 0.4:
					ciemne = true
	_check(fontanny == 3, "trzy ofiary to trzy fontanny piór (jest %d)" % fontanny)
	_check(ciemne, "piora cemani/marans sa ciemne, nie biale")
	_check(blood_on, "po napasci leci krew")
	# Plamy krwi zostaja na wybiegu, wiec sa dziecmi kontenera, nie lisa.
	# Plamy krwi leza w warstwie dekoracji POD zwierzetami, zeby nie zaslanialy
	# kur i nie wygladaly, jakby unosily sie w powietrzu.
	var splats := 0
	var splat_scale := Vector2.ONE
	var decals_children := _main.get_node("Farm/Decals").get_children()
	for child in decals_children:
		var sprite := child as Sprite2D
		if sprite != null and sprite.texture != null \
				and sprite.texture.resource_path.ends_with("blood_splat.svg"):
			splats += 1
			splat_scale = sprite.scale
	_check(splats > 0, "plamy krwi leza w warstwie dekoracji (jest %d)" % splats)
	var decals: Node2D = _main.get_node("Farm/Decals")
	var objects: Node2D = _main.get_node("Farm/Objects")
	_check(decals.get_index() > (_main.get_node("Farm/Ground") as Node2D).get_index(),
			"warstwa plam jest NAD trawa, inaczej plam w ogole nie widac")
	_check(decals.get_index() < objects.get_index(),
			"warstwa plam jest POD zwierzetami")
	# Urwane glowy wylatuja z miejsca napasci i laduja na wybiegu.
	var heads := 0
	for child in decals_children:
		var sprite := child as Sprite2D
		if sprite != null and sprite.texture != null \
				and sprite.texture.resource_path.ends_with("hen_head.svg"):
			heads += 1
	_check(heads > 0, "po napasci lataja urwane glowy (jest %d)" % heads)
	_check(splat_scale.y < splat_scale.x,
			"plama jest splaszczona, czyli lezy na ziemi (%.2f x %.2f)" % [splat_scale.x, splat_scale.y])
	_shot("lis_piora.png")

	# Napasc NIE konczy wizyty: lis poluje dalej, az skonczy mu sie czas.
	await _seconds(1.5)
	_check(_nodes_of_type("FarmFox").size() == 1, "po napasci lis zostaje i poluje dalej")
	_shot("lis_krew.png")

	# Ale po swoim czasie odchodzi sam, bez zadnego sygnalu z gry
	# (przeskakuje plot i chowa sie w krzakach - to trwa ok. 2 s).
	await _seconds(9.5)
	_check(_nodes_of_type("FarmFox").is_empty(), "lis odchodzi sam, gdy minie jego czas")

	# Lis zawrocony przez plot: ma przebiec i zniknac, nic nie zabierajac.
	var flock_before := Game.state.hen_count()
	Events.fox_repelled.emit()
	await _frames(20)
	var repelled := _nodes_of_type("FarmFox")
	_check(repelled.size() == 1, "zawrocony lis pokazuje sie na wybiegu")
	_check(not (repelled[0] as FarmFox).input_pickable,
			"zawroconego lisa nie da sie przeganiac, bo juz odchodzi")
	_shot("lis_zawrocony.png")
	await _seconds(9.0)
	_check(_nodes_of_type("FarmFox").is_empty(), "zawrocony lis sam znika z wybiegu")
	_check(Game.state.hen_count() == flock_before, "zawrocony lis nic nie zabral")


## Rozbudowa ma byc WIDOCZNA na farmie, nie tylko w panelu. Plot ma rosnac
## z kazdym poziomem obrony, a budynki zmieniac wyglad na progach 3 i 6.
func _test_upgrade_looks() -> void:
	var farm: Node2D = _main.get_node("Farm")
	var fence: Sprite2D = farm.get_node("Objects/FenceFront")

	var seen: Array[String] = []
	var feet: Array[float] = []
	var heights: Array[float] = []
	for level in 5:
		Game.state.guard_level = level
		farm._sync_buildings()
		await _frames(2)
		seen.append(fence.texture.resource_path)
		heights.append(float(fence.texture.get_height()))
		# Dol plotu musi zostac na tej samej linii trawy, inaczej wyzszy plot
		# zaklada sie na wybieg albo wisi w powietrzu.
		feet.append(fence.position.y + fence.offset.y + fence.texture.get_height())

	var unique := {}
	for path: String in seen:
		unique[path] = true
	_check(unique.size() == 5, "kazdy poziom plotu ma wlasny wyglad (jest %d)" % unique.size())

	var rosnie := true
	for i in range(1, heights.size()):
		if heights[i] <= heights[i - 1]:
			rosnie = false
	_check(rosnie, "kolejny plot jest wyzszy od poprzedniego")

	var rowno := true
	for value: float in feet:
		if absf(value - feet[0]) > 0.5:
			rowno = false
	_check(rowno, "dol plotu stoi na tej samej linii na kazdym poziomie")

	Game.state.guard_level = 0
	farm._sync_buildings()

	# Budynki: trzy wygladay, progi na poziomach 3 i 6.
	for node_name: String in ["Coop", "Incubator", "Storage"]:
		var building: Node2D = farm.get_node("Objects/" + node_name)
		var sprite: Sprite2D = building.get_node("Sprite")
		var id := String(building.building_id)
		var base_size: Vector2 = sprite.texture.get_size()
		var looks: Array[String] = []
		for level in [0, 2, 3, 5, 6, 8]:
			Game.state.set_building_level(id, level)
			farm._sync_buildings()
			await _frames(1)
			looks.append(sprite.texture.resource_path)
			_check(sprite.texture.get_size() == base_size,
					"'%s' lvl %d ma to samo plotno, wiec nie przeskakuje" % [id, level])
		_check(looks[0] == looks[1] and looks[2] == looks[3] and looks[4] == looks[5],
				"'%s' zmienia wyglad tylko na progach" % id)
		_check(looks[0] != looks[2] and looks[2] != looks[4],
				"'%s' ma trzy rozne wygladay rozbudowy" % id)
		Game.state.set_building_level(id, 0)
	farm._sync_buildings()


## Owczarek ma byc INNYM psem niz kundel i ma byc wiekszy.
func _test_dog_breeds() -> void:
	var farm: Node2D = _main.get_node("Farm")
	Game.state.dog_level = 1
	farm._sync_dog()
	await _frames(4)
	var dogs := _nodes_of_type("FarmDog")
	_check(dogs.size() == 1, "po kupieniu psa stoi na farmie dokladnie jeden (jest %d)" % dogs.size())
	if dogs.is_empty():
		return
	var dog: Node2D = dogs[0]
	var kundel: Texture2D = dog.get_node("Sprite").texture
	var maly: float = dog.scale.x * kundel.get_width()

	Game.state.dog_level = 2
	farm._sync_dog()
	await _frames(4)
	var owczarek: Texture2D = dog.get_node("Sprite").texture
	var duzy: float = dog.scale.x * owczarek.get_width()
	_check(owczarek != kundel, "owczarek to inny sprajt niz kundel")
	_check(duzy > maly * 1.12, "owczarek jest wyraznie wiekszy (%.0f vs %.0f)" % [duzy, maly])

	# Lis musi byc mniejszy od psa — wlasciciel zglaszal odwrotnie.
	# Skale czytamy ze scen, a nie wpisujemy w test — inaczej test przestaje
	# pilnowac czegokolwiek w chwili, w ktorej ktos zmieni rozmiar postaci.
	var scena_lisa: PackedScene = load("res://scenes/farm/fox.tscn")
	var lis: Node2D = scena_lisa.instantiate()
	var lis_szerokosc: float = lis.scale.x * FarmFox.BODY_WIDTH
	lis.free()
	_check(lis_szerokosc < maly,
			"lis jest mniejszy od kundla (%.0f vs %.0f)" % [lis_szerokosc, maly])
	_shot("psy.png")
	Game.state.dog_level = 0
	farm._sync_dog()


## Pies wygryziony lis ma odejsc OD RAZU, a zabity — zostac rozszarpany
## w kaluzy krwi. Wczesniej scena pilnowala wylacznie wlasnego zegara, wiec
## lis skrocony przez psa dalej stal na wybiegu.
func _test_fox_death() -> void:
	var decals: Node2D = _main.get_node("Farm/Decals")
	for child in decals.get_children():
		child.queue_free()
	await _frames(4)

	# 0. Licznik trafien nad lisem: bez niego nikt nie wie, ze lisa odgania
	# sie palcem. Koledzy zglaszali to jako pierwsza rzecz na liscie.
	# fox_visit_left musi byc ustawione recznie — sam sygnal tylko stawia
	# sprajt, a poke_fox() pyta stan gry, czy lis faktycznie jest na wybiegu.
	Game.state.fox_taps_left = 20
	Game.state.fox_visit_left = 60.0
	Events.fox_arrived.emit(5, 60.0)
	await _seconds(1.2)
	var lisy := _nodes_of_type("FarmFox")
	_check(lisy.size() == 1, "lis wszedl przed psem")
	if not lisy.is_empty():
		var licznik: Label = null
		for child in (lisy[0] as Node).get_children():
			if child is Label:
				licznik = child
		_check(licznik != null and licznik.visible and licznik.text == "20",
				"nad lisem stoi licznik trafien")
		(lisy[0] as FarmFox)._hit()
		await _frames(4)
		_check(licznik != null and licznik.text == "19", "licznik spada po trafieniu")
		_shot("lis_licznik.png")
		Game.state.fox_taps_left = 20
		Game.state.fox_visit_left = 0.0
	Events.fox_chased.emit()
	await _frames(4)
	var uciekajacy := _nodes_of_type("FarmFox")
	_check(not uciekajacy.is_empty() and (uciekajacy[0] as FarmFox).phase == FarmFox.Phase.LEAVE,
			"wygryziony lis od razu ucieka, nie czeka na swoj zegar")
	_check(uciekajacy.is_empty() or not (uciekajacy[0] as FarmFox).input_pickable,
			"uciekajacego lisa nie da sie juz klikac")
	await _seconds(4.0)
	_check(_nodes_of_type("FarmFox").is_empty(),
			"wygryziony lis przeskakuje plot i znika w krzakach")

	# 2. Zabity: krew, strzepy i zwloki, ktore znikaja dopiero po chwili.
	Game.state.fox_visit_left = 60.0
	Events.fox_arrived.emit(5, 60.0)
	await _seconds(1.2)
	var foxes := _nodes_of_type("FarmFox")
	_check(foxes.size() == 1, "drugi lis wszedl na wybieg")
	if foxes.is_empty():
		return
	var fox := foxes[0] as FarmFox
	var before := fox.position
	Events.fox_killed.emit()
	await _frames(30)
	_check((fox.get_node("Blood") as CPUParticles2D).emitting, "przy zabiciu leci krew")
	var czerwone := 0
	var najwieksza := 0.0
	for child in decals.get_children():
		var sprite := child as Sprite2D
		if sprite == null or sprite.texture == null:
			continue
		if not sprite.texture.resource_path.ends_with("blood_splat.svg"):
			continue
		czerwone += 1
		najwieksza = maxf(najwieksza, sprite.scale.x)
	_check(czerwone >= 8, "po lisie zostaje kaluza i strzepy (plam: %d)" % czerwone)
	_check(najwieksza >= 3.0, "kaluza po lisie jest wieksza niz po kurze (%.1f)" % najwieksza)
	_check(absf(fox.position.x - before.x) < 40.0,
			"zabity lis zostaje na miejscu, nie ucieka za ekran")
	var martwy: Vector2 = fox.rig().scale.abs()
	_check(martwy.y < martwy.x * 0.5,
			"zwloki lisa leza plasko na trawie (%.2f x %.2f)" % [martwy.x, martwy.y])
	_shot("lis_rozszarpany.png")
	await _seconds(3.6)
	_check(_nodes_of_type("FarmFox").is_empty(), "zwloki lisa w koncu znikaja")


## Od 12.18 lis najpierw czai sie w krzakach, potem podchodzi pod plot.
## Plot wygral - lis drapie i wraca w krzaki. Plot przegral - przeskakuje
## i poluje galopem. Wlasciciel: "zeby bylo widac, ze plot cos robi".
func _test_fox_lurk_and_fence() -> void:
	for node in _nodes_of_type("FarmFox"):
		node.queue_free()
	await _frames(4)
	var farm: Node2D = _main.get_node("Farm")
	var run: Rect2 = Simulation.run_area()
	Game.state.guard_level = 2
	farm._sync_buildings()
	Events.fox_lurking.emit(8.0)
	await _seconds(1.2)
	var lisy := _nodes_of_type("FarmFox")
	_check(lisy.size() == 1, "lis pojawia sie w krzakach")
	if lisy.is_empty():
		return
	var lis := lisy[0] as FarmFox
	_check(lis.phase == FarmFox.Phase.LURK, "lis najpierw czai sie (faza LURK)")
	_check(not lis.input_pickable, "lisa w krzakach nie da sie klikac")
	var najblizszy := INF
	for bush_name: String in ["BushLeftTop", "BushRightTop", "BushLeftBottom", "BushRightBottom"]:
		var bush := farm.get_node("Objects/" + bush_name) as Node2D
		najblizszy = minf(najblizszy, bush.position.distance_to(lis.position))
	_check(najblizszy < 80.0, "lis stoi przy krzaku (%.0f px)" % najblizszy)
	_check(not run.has_point(lis.position), "w krzakach lis jest poza wybiegiem")
	_shot("lis_w_krzakach.png")
	await _seconds(7.4)
	_check(lis.phase == FarmFox.Phase.AT_FENCE, "po czajeniu lis stoi pod plotem (faza %d)" % lis.phase)
	_check(not run.has_point(lis.position), "pod plotem lis jest jeszcze poza wybiegiem")
	_shot("lis_pod_plotem.png")
	var stado := Game.state.hen_count()
	Events.fox_repelled.emit()
	await _seconds(0.6)
	_check(lis.phase == FarmFox.Phase.TURN_BACK, "plot wygral: lis zawraca")
	_shot("lis_drapie_pod_plotem.png")
	await _seconds(6.0)
	_check(_nodes_of_type("FarmFox").is_empty(), "zawrocony lis znika w krzakach")
	_check(Game.state.hen_count() == stado, "zawrocony lis nic nie zabral")

	# Plot przegral: przeskok i galop. Lapy musza pracowac.
	Events.fox_lurking.emit(4.5)
	await _seconds(5.0)
	lisy = _nodes_of_type("FarmFox")
	_check(lisy.size() == 1, "drugi lis pod plotem")
	if lisy.is_empty():
		return
	lis = lisy[0] as FarmFox
	Game.state.fox_visit_left = 30.0
	Game.state.fox_taps_left = 20
	Events.fox_arrived.emit(3, 30.0)
	await _seconds(0.25)
	_check(lis.phase == FarmFox.Phase.ENTER, "lis przeskakuje plot")
	_shot("lis_skacze_przez_plot.png")
	await _seconds(1.0)
	_check(lis.phase == FarmFox.Phase.HUNT, "po skoku lis poluje na wybiegu")
	_check(run.grow(10.0).has_point(lis.position), "lis jest na wybiegu")
	var lapa := lis.rig().get_node("Body/Front/Leg_front_near") as Node2D
	var katy: Array[float] = []
	for i in 24:
		katy.append(lapa.rotation)
		await _seconds(0.05)
	var rozrzut: float = katy.max() - katy.min()
	_check(rozrzut > 0.4, "lapy pracuja w biegu (rozrzut %.2f rad)" % rozrzut)
	_shot("lis_galop.png")
	Game.state.fox_visit_left = 0.0
	await _seconds(4.0)
	_check(_nodes_of_type("FarmFox").is_empty(),
			"po koncu wizyty w grze lis sam odchodzi, bez sygnalu (blad z 272180)")
	Game.state.guard_level = 0
	farm._sync_buildings()


## Panele kurnika i magazynu na farmie jak u wlasciciela (22 kury, magazyn
## na poziomie 1). Wlasciciel zglosil, ze "cena paszy wyglada blednie".
func _test_feed_panels() -> void:
	Game.state.chickens.clear()
	for i in 22:
		Game.state.chickens.append(Chicken.create("leghorn"))
	Game.state.chickens.append(Chicken.create("leghorn", true))
	Game.state.storage_level = 1
	Game.state.feed = 1040.0
	Game.state.money = 1431.0
	for id: String in ["coop", "storage"]:
		Events.building_tapped.emit(id, null)
		await _frames(20)
		var rows: Node = _main.get_node("Hud/Root/BuildingPanel/Sheet/Content/Scroll/Gutter/Scrollable/Rows")
		var teksty: Array[String] = []
		for label in rows.find_children("*", "Label", true, false):
			if (label as Label).visible and not (label as Label).text.is_empty():
				teksty.append((label as Label).text)
		var calosc := " | ".join(teksty)
		if id == "storage":
			_check(not calosc.contains(" 0 zł/kg"), "cena paszy nie wychodzi jako 0 zl/kg (%s)" % calosc)
			# Cena za kilogram liczona z konfiguracji, nie wpisana na sztywno -
			# wlasciciel sam zmienia ceny w balance.json.
			var za_kg := NumberFormat.small_money(float(Game.state.feed_pack()["per_kg"])) + "/kg"
			_check(calosc.contains(za_kg) and calosc.contains("rabat 10%"),
					"magazyn poziom 1: %s i rabat 10%% (%s)" % [za_kg, calosc])
		var akcje: Node = _main.get_node("Hud/Root/BuildingPanel/Sheet/Content/Scroll/Gutter/Scrollable/Actions")
		var przyciski: Array[String] = []
		for b in akcje.find_children("*", "Button", true, false):
			przyciski.append((b as Button).text)

		_shot("panel_%s.png" % id)
		Events.notice.emit("")
		var panel: Node = _main.get_node("Hud/Root/BuildingPanel")
		if panel.has_method("close"):
			panel.close()
		await _frames(20)
