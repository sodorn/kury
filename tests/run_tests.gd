extends Node
## Testy logiki, danych i sceny farmy (bez okna):
##   godot --headless --path . res://tests/tests.tscn
## Kod wyjscia 0 = wszystko OK, 1 = sa bledy.
##
## Testy uruchamiamy jako scene, a nie przez `-s`, bo skrypt podany w `-s`
## kompiluje sie zanim zarejestruja sie autoloady (Events, Game) i wtedy
## skrypty scen nie daja sie zaladowac.

var _failed := 0
var _passed := 0


func _ready() -> void:
	# 13.0: testy ida w dzien, niezaleznie od godziny uruchomienia.
	Daylight.force = 0
	# Testy NIGDY na prawdziwy serwer (patrz Cloud.use_test_server).
	Cloud.use_test_server()
	_check(Cloud.is_test_server(), "testy rozmawiaja tylko z martwym adresem, nie z baza graczy")
	# Gra przy starcie wczytuje zapis; testy maja ruszac od stanu poczatkowego.
	SaveGame.clear()
	Game.new_game()
	_test_number_format()
	_test_farm_state()
	_test_data_files()
	_test_farm_scene()
	_test_simulation()
	_test_economy()
	_test_save()
	_test_offline()
	_test_incubator()
	_test_shop_is_open()
	_test_hunger()
	_test_disease()
	_test_fox()
	_test_vet_and_selling()
	_test_incubator_upgrade()
	_test_win()
	_test_offline_eggs()
	_test_roosters()
	_test_coop_limit()
	_test_server_diagnosis()
	_test_incubate_without_flock()
	_test_retry_same_code()
	_test_body_unpacking()
	_test_dog()
	_test_dog_in_action()
	_test_dog_offline()
	_test_egg_lots()
	_test_breed_gating()
	_test_guard_migration()
	_test_fox_return_speed()
	_test_upgrade_ladders()
	_test_upgrades_file()
	_test_v13_basics()
	_test_night()
	_test_egg_spoilage()
	_test_egg_capacity()
	_test_vaccine_price()
	_test_require_code_after_break()
	_test_failed_restore_keeps_identity()
	_test_push_guards()
	_test_event_rules()
	_test_starving_farm()
	_test_lay_fairness()
	_test_time_gap()
	_test_buildings()
	_test_farm_code()
	_test_instrukcja_aktualna()
	_test_updater()
	_test_strings()
	_test_money_format()
	_test_hatch_sex()
	_test_fox_lurk()
	_test_fox_massacre()
	_test_game_over()
	_test_away_fox_and_report()
	_test_fox_left_and_victims()
	_test_construction()
	_test_real_time_texts()
	SaveGame.clear()
	print("TESTY: %d OK, %d BLEDOW" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("BLAD: " + label)


## Stan oderwany od autoloadu Game, zeby testy nie zaleznialy od siebie.
## Stado samych kur, BEZ kogutow. Uwaga: takie stado nie zniesie ani jednego
## jajka — od wersji 10.0 kura potrzebuje koguta swojej rasy. Do testow
## produkcji jaj sluzy `_laying_state`.
## Ustawia zdarzenie ("fox" albo "disease") tak, zeby na pewno wypadlo
## w najblizszym kroku sekundowym: zero karencji i sredni odstep przyciety
## do jednej sekundy. Zmiana dotyczy wczytanej kopii balansu, wiec kazdy test,
## ktory z tego korzysta, konczy sie `GameData.reload()`.
func _force_event(kind: String) -> void:
	var cfg: Dictionary = GameData.balance().get(kind, {})
	cfg["grace_minutes"] = 0.0
	cfg["mean_minutes"] = 0.0


## Dodatkowo nabija licznik suchych minut, zeby krzywa narastania byla juz na
## maksimum i zdarzenie wypadlo w najblizszym kroku na pewno, a nie "zwykle".
func _arm_event(state: FarmState, kind: String) -> void:
	_force_event(kind)
	state.event_dry[kind] = 100000.0


## GameData.balance() zwraca WSPOLNY slownik, wiec _force_event i _never_event
## zmieniaja ustawienia dla wszystkich dalszych testow. Te dwie funkcje
## pozwalaja oddac stan nietkniety. Bez tego _test_event_rules widzialo
## karencje lisa rowna zeru i oblewalo sie przez test, ktory skonczyl sie
## wczesniej.
func _snapshot_event(kind: String) -> Dictionary:
	return (GameData.balance().get(kind, {}) as Dictionary).duplicate(true)


func _restore_event(kind: String, snapshot: Dictionary) -> void:
	var cfg: Dictionary = GameData.balance().get(kind, {})
	cfg.clear()
	cfg.merge(snapshot)


## Odwrotnie: zdarzenie nie wypadnie przez cala rozsadna dlugosc testu.
## Wylacza zdarzenie na czas testu. Od wersji 12.1 lis i choroba chodza na
## kostce (`active_chance` / `offline_chance`), a nie na dawnych
## `mean_minutes` / `hard_minutes`. Ta funkcja zerowala stare klucze, ktorych
## juz nie ma, wiec NIC nie wylaczala — test ksiegowania jaj losowo dostawal
## lisa, ktory zjadal stado, i swiecil sie na czerwono bez bledu w kodzie.
func _never_event(kind: String) -> void:
	var cfg: Dictionary = GameData.balance().get(kind, {})
	cfg["chance"] = 0.0
	cfg["min_hens"] = 1000000
	cfg["grace_minutes"] = 1000000.0
	# Choroba od 12.20 chodzi na krzywej szansy od wielkosci stada.
	cfg["rate_per_hour"] = [[0, 0.0]]
	# Lis: bez rzezi.
	cfg["massacre_chance"] = 0.0


func _fresh_state(hens: Array[String] = ["leghorn"], feed := 100.0) -> FarmState:
	var state := FarmState.new()
	state.money = 100
	state.feed = feed
	for breed_id in hens:
		state.chickens.append(Chicken.create(breed_id))
	return state


## To samo stado plus jeden kogut kazdej wystepujacej rasy, czyli stado, ktore
## faktycznie niesie. Koguty sa zaszczepione, zeby nie chorowaly w testach,
## ktore mierza co innego.
## Stan do testow ZNOSZENIA i ksiegowania jaj. Dostaje najwiekszy magazyn,
## bo te testy nie sa o limicie pojemnosci — przy domyslnych 200 jajach
## limit przycinalby wyniki i testy mowilyby o czym innym, niz deklaruja.
## Sam limit ma wlasny test: `_test_egg_capacity`.
func _laying_state(hens: Array[String] = ["leghorn"], feed := 100.0) -> FarmState:
	var state := _fresh_state(hens, feed)
	state.storage_level = (GameData.balance().get("buildings", {}).get(
			"storage", {}).get("upgrades", []) as Array).size()
	var added := {}
	for breed_id in hens:
		if added.has(breed_id):
			continue
		added[breed_id] = true
		var rooster := Chicken.create_rooster(breed_id)
		rooster.vaccinated = true
		state.chickens.append(rooster)
	return state


func _test_number_format() -> void:
	_check(NumberFormat.grouped(0) == "0", "grouped(0)")
	_check(NumberFormat.grouped(999) == "999", "grouped(999)")
	_check(NumberFormat.grouped(1000) == "1 000", "grouped(1000)")
	_check(NumberFormat.grouped(1234567) == "1 234 567", "grouped(1234567)")
	_check(NumberFormat.grouped(-12345) == "-12 345", "grouped(-12345)")


func _test_farm_state() -> void:
	var state := FarmState.from_start_config({"money": 100.0, "feed": 20, "hens": ["leghorn", "leghorn"]})
	_check(state.money == 100, "money z configu")
	_check(state.egg_count() == 0, "brakujace pole = 0")
	_check(state.hen_count() == 2, "hen_count")
	_check(is_equal_approx(state.feed, 20.0), "feed z configu")
	_check(Game.state != null and Game.state.laying_hen_count() == 3,
			"Game wystartowal z 3 kurami z balance.json")
	# Nowa farma musi dostac koguta razem z kurami, inaczej nie zniosla by
	# ani jednego jajka i gra wygladalaby na zepsuta od pierwszej minuty.
	_check(Game.state != null and Game.state.has_rooster("leghorn"),
			"nowa farma ma koguta, wiec kury maja dla kogo niesc")


func _test_data_files() -> void:
	_check(GameData.balance().has("start"), "balance.json ma sekcje start")
	_check(GameData.buildings().size() == 4, "buildings.json ma 4 budynki")
	_check(GameData.breeds().size() >= 8, "breeds.json ma co najmniej 8 ras")
	var translation := load("res://data/strings.pl.translation") as Translation
	_check(translation != null, "tlumaczenie pl wczytane")

	var ids := {}
	for def: Dictionary in GameData.buildings():
		var id: String = def.get("id", "")
		_check(id != "" and not ids.has(id), "unikalne id budynku: '%s'" % id)
		ids[id] = true
		for key in ["name", "desc"]:
			_check(_has_text(translation, def.get(key, "")), "tekst %s" % def.get(key, ""))

	for breed: Dictionary in GameData.breeds():
		var breed_id: String = breed.get("id", "")
		_check(breed_id != "", "rasa ma id")
		_check(ResourceLoader.exists(breed.get("sprite", "")), "grafika rasy '%s'" % breed_id)
		_check(float(breed.get("egg_seconds", 0)) > 0.0, "czas znoszenia rasy '%s'" % breed_id)
		var buy := int(breed.get("price", 0))
		var sell := int(breed.get("sell_price", 0))
		_check(buy > 0 and sell > 0 and sell < buy, "cena kupna > ceny sprzedazy dla '%s'" % breed_id)
		_check(_has_text(translation, breed.get("rarity", "")), "nazwa rzadkosci rasy '%s'" % breed_id)
		_check(float(breed.get("incubate_seconds", 0)) > 0.0, "czas wykluwania rasy '%s'" % breed_id)
		_check(float(breed.get("grow_seconds", 0)) > 0.0, "czas wzrostu rasy '%s'" % breed_id)
		for required_id: String in Dictionary(breed.get("unlock", {})).get("breeds", []):
			_check(not GameData.breed(required_id).is_empty(),
					"rasa '%s' wymaga istniejacej rasy '%s'" % [breed_id, required_id])
		for key in ["name", "desc"]:
			_check(_has_text(translation, breed.get(key, "")), "tekst %s" % breed.get(key, ""))

	# Kazda rasa z sekcji start musi istniec w breeds.json.
	for breed_id: String in GameData.balance().get("start", {}).get("hens", []):
		_check(not GameData.breed(breed_id).is_empty(), "rasa startowa '%s' istnieje" % breed_id)

	# Teksty uzywane przez panel.
	for key in ["PANEL_HENS", "PANEL_CHICKS", "PANEL_FARM_AGE", "PANEL_INCUBATE",
			"PANEL_HATCHING", "PANEL_GROWING", "PANEL_LOCKED", "PANEL_NEED",
			"PANEL_NEED_MONEY", "PANEL_NEED_DAYS", "PANEL_NEED_HENS", "PANEL_NEED_FEED",
			"PANEL_NEED_BREED", "PANEL_FARM_CODE", "HINT_BREED_UNLOCKED", "PANEL_FEED_LEFT", "PANEL_EGGS_STORED", "PANEL_EGGS_WORTH",
			"PANEL_NEXT_EGG", "PANEL_SELL_EGGS", "PANEL_BUY_FEED", "PANEL_BUY_HEN",
			"PANEL_SOLD", "PANEL_FEED_BOUGHT", "PANEL_HEN_BOUGHT", "PANEL_SELL_HEN",
			"PANEL_HEN_SOLD", "HINT_NO_FEED", "HINT_WELCOME_BACK"]:
		_check(_has_text(translation, key), "tekst panelu %s" % key)


func _has_text(translation: Translation, key: String) -> bool:
	return translation != null and key != "" and translation.get_message(key) != &""


## Scena farmy musi zawierac budynki (zeby bylo je widac w edytorze),
## a kazdy z nich grafike i id istniejace w data/buildings.json.
func _test_farm_scene() -> void:
	var farm: Node2D = load("res://scenes/farm/farm.tscn").instantiate()
	var found := {}
	for child in farm.get_node("Objects").get_children():
		var building := child as Building
		if building == null:
			continue
		found[building.building_id] = true
		_check(not GameData.building(building.building_id).is_empty(),
				"budynek '%s' ma wpis w buildings.json" % building.building_id)
		var sprite := building.get_node("Sprite") as Sprite2D
		_check(sprite != null and sprite.texture != null, "budynek '%s' ma grafike" % building.building_id)
	for def: Dictionary in GameData.buildings():
		_check(found.has(def.get("id", "")), "budynek '%s' jest w scenie farmy" % def.get("id", ""))
	farm.free()


func _test_simulation() -> void:
	var seconds := float(GameData.breed("leghorn").get("egg_seconds", 0.0))

	# Jedna kura po czasie znoszenia daje dokladnie jedno jajko.
	var state := _laying_state()
	var result := Simulation.advance(state, seconds)
	_check(int(result["eggs_laid"]) == 1, "jedna kura, jedno jajko po %.0f s" % seconds)
	_check(state.eggs_on_ground.size() == 1, "jajko wyladowalo na wybiegu")
	_check(state.eggs_on_ground[0] == "leghorn", "jajko pamieta rase kury")
	_check(state.egg_count() == 0, "jajko nie trafia od razu do magazynu")

	# Przed czasem nie ma nic.
	var early := _fresh_state()
	_check(int(Simulation.advance(early, seconds - 5.0)["eggs_laid"]) == 0, "przed czasem brak jaja")

	# Trzy kury przez trzy cykle: dziewiec jaj.
	var flock := _laying_state(["leghorn", "leghorn", "leghorn"])
	_check(int(Simulation.advance(flock, seconds * 3.0)["eggs_laid"]) == 9, "3 kury x 3 cykle = 9 jaj")

	# Pasza sie zuzywa.
	var eating := _fresh_state(["leghorn"], 10.0)
	Simulation.advance(eating, 60.0)
	var expected := 10.0 - float(GameData.balance().get("economy", {}).get("feed_per_hen_minute", 0.0))
	_check(absf(eating.feed - expected) < 0.01, "zuzycie paszy przez minute")

	# Bez paszy nie ma jaj i jest sygnal o braku.
	var hungry := _fresh_state(["leghorn"], 0.0)
	var hungry_result := Simulation.advance(hungry, seconds * 2.0)
	_check(int(hungry_result["eggs_laid"]) == 0, "brak paszy = brak jaj")
	_check(bool(hungry_result["out_of_feed"]), "brak paszy jest raportowany")

	# Wynik nie zalezy od tego, czy liczymy jednym duzym krokiem czy wieloma
	# malymi. Kury szczepimy, zeby losowe choroby nie rozjechaly obu przebiegow
	# — ten test pilnuje calkowania czasu, a nie zdarzen losowych.
	var big := _fresh_state(["leghorn", "rhode"])
	var small := _fresh_state(["leghorn", "rhode"])
	for pair: FarmState in [big, small]:
		for bird: Chicken in pair.chickens:
			bird.vaccinated = true
	Simulation.advance(big, 600.0)
	for i in 600:
		Simulation.advance(small, 1.0)
	_check(big.eggs_on_ground.size() == small.eggs_on_ground.size(),
			"ten sam wynik przy roznych krokach czasu")

	# Pelny wybieg wstrzymuje znoszenie.
	var capacity := int(GameData.balance().get("run", {}).get("max_eggs_on_ground", 24))
	var full := _fresh_state(["leghorn"])
	for i in capacity:
		full.eggs_on_ground.append("leghorn")
	_check(int(Simulation.advance(full, seconds * 2.0)["eggs_laid"]) == 0, "pelny wybieg wstrzymuje znoszenie")
	_check(full.eggs_on_ground.size() == capacity, "liczba jaj na wybiegu nie przekracza limitu")


func _test_economy() -> void:
	var economy: Dictionary = GameData.balance().get("economy", {})

	# Zbieranie: z wybiegu do magazynu.
	Game.new_game()
	Game.state.eggs_on_ground = ["leghorn", "leghorn"] as Array[String]
	_check(Game.collect_egg_of_breed("leghorn"), "zbieranie jajka udaje sie, gdy jest co zbierac")
	_check(int(Game.state.eggs.get("leghorn", 0)) == 1 and Game.state.eggs_on_ground.size() == 1,
			"jajko przeszlo na stan magazynu")
	_check(not Game.collect_egg_of_breed("cemani"), "nie ma jaj rasy, ktorej nie ma na wybiegu")
	Game.collect_egg_of_breed("leghorn")
	_check(not Game.collect_egg_of_breed("leghorn"), "pusty wybieg: nie ma czego zbierac")

	# Sprzedaz.
	Game.new_game()
	Game.state.eggs = {"leghorn": 4}
	var money_before := Game.state.money
	var earned := Game.sell_eggs()
	_check(is_equal_approx(earned, 4.0 * float(GameData.breed("leghorn").get("egg_value", 0))),
			"zarobek ze sprzedazy 4 jaj")
	_check(Game.state.money == money_before + earned, "pieniadze wzrosly o zarobek")
	_check(Game.state.egg_count() == 0, "magazyn jaj pusty po sprzedazy")
	_check(is_zero_approx(Game.sell_eggs()), "sprzedaz bez jaj nic nie daje")

	# Zakup paszy.
	Game.new_game()
	var feed_before := Game.state.feed
	Game.state.money = float(economy.get("feed_pack_price", 0))
	_check(Game.buy_feed(), "zakup paszy za dokladna kwote")
	_check(absf(Game.state.feed - (feed_before + float(economy.get("feed_pack_size", 0)))) < 0.01, "pasza doliczona")
	_check(is_zero_approx(Game.state.money), "pieniadze pobrane")
	_check(not Game.buy_feed(), "brak pieniedzy blokuje zakup paszy")

	# Zakup kury: tylko rasa odblokowana.
	Game.new_game()
	var hens_before := Game.state.hen_count()
	Game.state.money = float(GameData.breed("leghorn").get("price", 0))
	_check(Game.buy_hen("leghorn"), "zakup odblokowanej rasy za dokladna kwote")
	_check(Game.state.hen_count() == hens_before + 1, "kura dolaczyla do stada")
	_check(is_zero_approx(Game.state.money), "pieniadze za kure pobrane")
	_check(not Game.buy_hen("leghorn"), "brak pieniedzy blokuje zakup kury")
	_check(not Game.buy_hen("nieistniejaca"), "nieznana rasa nie da sie kupic")
	Game.state.money = 999999
	_open_all_breeds()
	_check(Game.buy_hen("cemani"), "najdrozsza rasa do kupienia, gdy stac gracza")

	# Kogut jest dwa razy drozszy od kury swojej rasy. Jeden kogut obsluguje
	# cale stado, wiec przy cenie kury byl najtanszym obowiazkowym zakupem
	# w grze — i dlatego nie bylo czego wazyc przy zakupie.
	var mnoznik: float = float(GameData.balance().get("economy", {})
			.get("rooster_price_multiplier", 2.5))
	_check(mnoznik >= 1.0 and mnoznik <= 20.0,
			"mnoznik ceny koguta trzyma sie rozsadku (%.2f)" % mnoznik)
	for breed: Dictionary in GameData.breeds():
		var id := String(breed.get("id", ""))
		var kura := FarmState.hen_buy_price(id, false)
		var kogut := FarmState.hen_buy_price(id, true)
		_check(is_equal_approx(kogut, kura * mnoznik),
				"kogut rasy '%s' kosztuje %.0f%% ceny kury (%.0f vs %.0f)"
						% [id, mnoznik * 100.0, kogut, kura])
		_check(is_equal_approx(kura, float(breed.get("price", 0))),
				"cena kury rasy '%s' bez zmian" % id)

	# Sprzedaz koguta: ten sam mnoznik co w kupnie, wiec tak jak kura
	# schodzi za ~70% swojej ceny kupna (wlasciciel, 24.11).
	for breed: Dictionary in GameData.breeds():
		var id2 := String(breed.get("id", ""))
		var kura_s := FarmState.hen_sell_price(id2)
		var kogut_s := FarmState.hen_sell_price(id2, false, true)
		_check(is_equal_approx(kogut_s, kura_s * mnoznik),
				"kogut rasy '%s' sprzedaje sie za %.0f%% ceny kury (%.0f vs %.0f)"
						% [id2, mnoznik * 100.0, kogut_s, kura_s])
		_check(kogut_s < FarmState.hen_buy_price(id2, true),
				"kogut rasy '%s': sprzedaz tansza niz kupno" % id2)
	_check(is_zero_approx(FarmState.hen_sell_price("leghorn", true, true)),
			"chory kogut nie idzie po cenie zdrowego")

	# I to samo przy kasie, nie tylko w tabelce.
	Game.new_game()
	_open_all_breeds()
	var cena_kury := FarmState.hen_buy_price("leghorn", false)
	Game.state.money = cena_kury * mnoznik - 1.0
	_check(not Game.buy_hen("leghorn", true),
			"na koguta nie wystarcza kwota o zlotowke za mala")
	Game.state.money = cena_kury * mnoznik
	var kogutow_przed := Game.state.rooster_count()
	_check(Game.buy_hen("leghorn", true), "kogut do kupienia za podwojna cene")
	_check(Game.state.rooster_count() == kogutow_przed + 1, "kogut dolaczyl do stada")
	_check(is_zero_approx(Game.state.money), "za koguta pobrano pelna cene koguta")
	var za_koguta := Game.sell_hen("leghorn", true)
	_check(is_equal_approx(za_koguta, FarmState.hen_sell_price("leghorn", false, true)),
			"sprzedaz koguta przy kasie daje cene koguta (%.0f zl)" % za_koguta)

	# Wartosc jaj zalezy od stada.
	Game.new_game()
	Game.state.eggs = {"leghorn": 1}
	_check(is_equal_approx(Game.state.eggs_value(), float(GameData.breed("leghorn").get("egg_value", 0))),
			"wartosc jajka przy stadzie leghornow")
	Game.new_game()


## Zapis musi przetrwac restart gry i nie moze sie wywracac na smieciach.
func _test_save() -> void:
	var path := "user://test_save.json"
	SaveGame.clear(path)
	_check(not SaveGame.has_save(path), "brak zapisu na starcie testu")
	_check(SaveGame.load_state(path).is_empty(), "odczyt bez pliku zwraca pustke")

	var state := _fresh_state(["leghorn", "cemani"], 12.5)
	state.money = 777
	state.eggs = {"leghorn": 5}
	state.eggs_on_ground = ["leghorn", "rhode", "leghorn"] as Array[String]
	state.chickens[0].since_last_egg = 13.0
	_check(SaveGame.save_state(state, path), "zapis sie udaje")

	var loaded := SaveGame.load_state(path)
	_check(not loaded.is_empty(), "odczyt zwraca dane")
	var back: FarmState = loaded["state"]
	_check(back.money == 777, "pieniadze po odczycie")
	_check(int(back.eggs.get("leghorn", 0)) == 5 and back.eggs_on_ground.size() == 3,
			"jaja po odczycie")
	_check(back.eggs_on_ground.count("rhode") == 1, "rasa jajka na wybiegu po odczycie")
	_check(absf(back.feed - 12.5) < 0.01, "pasza po odczycie")
	_check(back.hen_count() == 2, "liczba kur po odczycie")
	_check(back.chickens[0].breed_id == "leghorn" and back.chickens[1].breed_id == "cemani",
			"rasy kur po odczycie")
	_check(absf(back.chickens[0].since_last_egg - 13.0) < 0.01, "postep kury po odczycie")
	_check(float(loaded["elapsed"]) >= 0.0, "czas od zapisu nie jest ujemny")

	# Uszkodzony plik nie moze wywrocic gry.
	var broken := FileAccess.open(path, FileAccess.WRITE)
	broken.store_string("{to nie jest json")
	broken.close()
	_check(SaveGame.load_state(path).is_empty(), "uszkodzony zapis jest pomijany")

	# Zapis z nowszej wersji gry tez pomijamy, zamiast zgadywac uklad pol.
	var future := FileAccess.open(path, FileAccess.WRITE)
	future.store_string(JSON.stringify({"version": SaveGame.VERSION + 5, "money": 10}))
	future.close()
	_check(SaveGame.load_state(path).is_empty(), "zapis z nowszej wersji jest pomijany")

	# Kura rasy, ktorej juz nie ma w breeds.json, znika — reszta zapisu zostaje.
	var odd := FileAccess.open(path, FileAccess.WRITE)
	odd.store_string(JSON.stringify({
		"version": SaveGame.VERSION, "saved_at": Time.get_unix_time_from_system(),
		"money": 5, "eggs": {}, "eggs_on_ground": [], "feed": 1.0,
		"chickens": [{"breed": "dinozaur", "since_last_egg": 0.0}, {"breed": "leghorn", "since_last_egg": 0.0}]}))
	odd.close()
	var repaired: FarmState = SaveGame.load_state(path)["state"]
	_check(repaired.hen_count() == 1 and repaired.chickens[0].breed_id == "leghorn",
			"nieznana rasa w zapisie jest pomijana")
	SaveGame.clear(path)


## Czas spedzony poza gra ma sie liczyc tak samo jak czas na ekranie,
## ale nie wiecej niz limit z balance.json.
func _test_offline() -> void:
	var seconds := float(GameData.breed("leghorn").get("egg_seconds", 0.0))
	var max_hours := float(GameData.balance().get("offline", {}).get("max_hours", 8.0))
	_check(max_hours > 0.0, "balance.json ma limit godzin offline")

	# Dwie godziny nieobecnosci przy duzym zapasie paszy. Kura zaszczepiona,
	# bo inaczej moze w tym czasie zachorowac i przestac niesc — test
	# sprawdza limit wybiegu, a nie choroby.
	var away := _laying_state(["leghorn"], 10000.0)
	for hen: Chicken in away.chickens:
		hen.vaccinated = true
	var laid := int(Simulation.advance(away, 7200.0)["eggs_laid"])
	var capacity := int(GameData.balance().get("run", {}).get("max_eggs_on_ground", 24))
	# Limit wybiegu dotyczy juz tylko tego, ile jaj na nim lezy; nadmiar idzie
	# do magazynu, wiec przez dwie godziny kura znosi pelna pule.
	_check(laid == int(7200.0 / seconds), "dwie godziny to pelna pula jaj (%d)" % laid)
	_check(away.eggs_on_ground.size() <= capacity, "na wybiegu lezy najwyzej tyle, ile miesci")
	_check(away.egg_count() > 0, "reszta czeka w magazynie")

	# Limit: nieobecnosc dluzsza niz `max_hours` liczy sie jak `max_hours`.
	var long_state := _fresh_state(["leghorn"], 10000.0)
	for hen: Chicken in long_state.chickens:
		hen.vaccinated = true
	var over_limit := (max_hours + 48.0) * 3600.0
	var clamped := clampf(over_limit, 0.0, max_hours * 3600.0)
	_check(clamped == max_hours * 3600.0, "czas offline jest przycinany do limitu")
	Simulation.advance(long_state, clamped)
	_check(long_state.eggs_on_ground.size() <= capacity,
			"po dlugiej przerwie wybieg nie przekracza limitu")

	# Cofniety zegar nie moze dawac ujemnego postepu.
	var back_in_time := _fresh_state(["leghorn"], 100.0)
	var before := back_in_time.feed
	Simulation.advance(back_in_time, -500.0)
	_check(absf(back_in_time.feed - before) < 0.001, "cofniety zegar niczego nie zmienia")


## Inkubator: jaja -> pisklę -> dorosla kura.
func _test_incubator() -> void:
	Game.new_game()
	var cost := Game.eggs_per_chick()
	Game.state.eggs = {"leghorn": cost}

	_check(not Game.incubate("cemani"), "nie da sie wlozyc jaj rasy, ktorej sie nie ma")
	_check(Game.incubate("leghorn"), "wlozenie jaj posiadanej rasy udaje sie")
	_check(Game.state.egg_count() == 0, "jaja znikaja z magazynu")
	_check(Game.state.incubating.size() == 1, "partia trafila do inkubatora")
	_check(not Game.incubate("leghorn"), "bez jaj nie da sie wlozyc kolejnej partii")

	# Limit miejsc.
	Game.new_game()
	Game.state.eggs = {"leghorn": cost * (Game.incubator_slots() + 1)}
	for i in Game.incubator_slots():
		_check(Game.incubate("leghorn"), "miejsce %d w inkubatorze" % (i + 1))
	_check(not Game.incubate("leghorn"), "pelny inkubator nie przyjmuje wiecej jaj")

	# Przebieg w czasie: wyklucie, potem dorastanie.
	var state := _fresh_state(["leghorn"], 10000.0)
	state.incubating.append(EggBatch.create("leghorn", 1))
	var incubate_seconds := float(GameData.breed("leghorn").get("incubate_seconds", 0.0))
	var grow_seconds := float(GameData.breed("leghorn").get("grow_seconds", 0.0))
	var hens_before := state.hen_count()

	var result := Simulation.advance(state, incubate_seconds)
	_check(int(result["hatched"]) == 1, "po czasie wykluwania powstaje pisklę")
	_check(state.incubating.is_empty() and state.chicks.size() == 1, "partia zamienia sie w pisklę")

	result = Simulation.advance(state, grow_seconds)
	_check(int(result["grown_up"]) == 1, "pisklę dorasta")
	_check(state.chicks.is_empty(), "pisklę znika z listy piskląt")
	_check(state.hen_count() == hens_before + 1, "dorosla kura dolacza do stada")

	# Kura jedwabista przyspiesza inkubator.
	var plain := _fresh_state(["leghorn"], 10000.0)
	var silky := _fresh_state(["leghorn", "jedwabista"], 10000.0)
	plain.incubating.append(EggBatch.create("leghorn", 1))
	silky.incubating.append(EggBatch.create("leghorn", 1))
	Simulation.advance(plain, incubate_seconds * 0.75)
	Simulation.advance(silky, incubate_seconds * 0.75)
	_check(silky.chicks.size() > plain.chicks.size(), "jedwabista przyspiesza wykluwanie")

	# Pisklęta jedza, ale mniej niz dorosle.
	var with_chick := _fresh_state(["leghorn"], 100.0)
	var adults_only := with_chick.feed_per_minute()
	with_chick.chicks.append(Chick.create("leghorn"))
	_check(with_chick.feed_per_minute() > adults_only, "pisklę tez zjada pasze")
	_check(with_chick.feed_per_minute() < adults_only * 2.0, "pisklę zjada mniej niz dorosla kura")
	Game.new_game()


## Sklep bez barier: kazda rasa stoi w nim od pierwszej minuty, a cena jest
## jedna, niezaleznie od tego, ktora to sztuka. Dawniej rasy odblokowywaly
## sie po przekroczeniu progu pieniedzy — gracz czytal te progi jak ceny
## i slusznie uznal za sztuczne.
func _test_shop_is_open() -> void:
	var state := _fresh_state(["leghorn"], 10.0)
	for breed: Dictionary in GameData.breeds():
		var breed_id: String = breed.get("id", "")
		_check(state.is_unlocked(breed_id), "rasa '%s' dostepna od startu" % breed_id)
		_check(not breed.has("unlock"), "rasa '%s' nie ma juz progu odblokowania" % breed_id)
	_check(Simulation.check_unlocks(state).is_empty(), "nie ma czego odblokowywac")

	# Cena kupna i sprzedazy jest ta sama przy pierwszej i przy kolejnej sztuce.
	Game.new_game()
	Game.state.money = 100000.0
	Game.state.chickens.clear()
	_open_all_breeds()
	var price := float(GameData.breed("cemani").get("price", 0))
	var before := Game.state.money
	_check(Game.buy_hen("cemani"), "najdrozsza rasa do kupienia od razu")
	var first_cost := before - Game.state.money
	before = Game.state.money
	_check(Game.buy_hen("cemani"), "druga sztuka tej samej rasy")
	var second_cost := before - Game.state.money
	_check(is_equal_approx(first_cost, price) and is_equal_approx(second_cost, price),
			"obie sztuki kosztuja tyle samo")
	var sell := Game.sell_hen("cemani")
	_check(sell > price * 0.5, "sprzedaz oddaje wiecej niz polowe ceny zakupu")
	_check(is_equal_approx(sell, FarmState.hen_sell_price("cemani")), "stawka zgodna z breeds.json")

	# Historia rasy pokazuje sie raz, przy pierwszej sztuce.
	Game.new_game()
	Game.state.money = 100000.0
	Game.state.unlocked_breeds.clear()
	_open_all_breeds()
	_check(not Game.state.has_ever_owned("brahma"), "na starcie gracz nie mial tej rasy")
	Game.buy_hen("brahma")
	_check(Game.state.has_ever_owned("brahma"), "pierwsza sztuka zapisuje sie w kolekcji")
	Game.buy_hen("brahma")
	_check(Game.state.hens_of_breed("brahma") == 2, "druga sztuka tez trafia do stada")
	Game.new_game()

## Odblokowywanie ras: warunki musza byc spelnione w calosci.
func _test_unlocks() -> void:
	var state := _fresh_state(["leghorn"], 0.0)
	state.unlocked_breeds.clear()
	state.ensure_starting_unlocks()
	_check(state.is_unlocked("leghorn"), "rasa bez warunkow jest dostepna od startu")
	_check(not state.is_unlocked("rhode"), "rasa z warunkami startuje zablokowana")

	var need: Dictionary = GameData.breed("rhode").get("unlock", {})
	state.money = float(need.get("money", 0))
	_check(Simulation.check_unlocks(state).is_empty(), "same pieniadze nie wystarcza")

	while state.hen_count() < int(need.get("hens", 0)):
		state.chickens.append(Chicken.create("leghorn"))
	state.feed = float(need.get("feed", 0))
	state.days = int(need.get("days", 0))
	var fresh := Simulation.check_unlocks(state)
	_check(fresh.has("rhode"), "komplet warunkow odblokowuje rase")
	_check(state.is_unlocked("rhode"), "odblokowana rasa zostaje w stanie")
	_check(Simulation.check_unlocks(state).is_empty(), "rasa odblokowuje sie tylko raz")

	# Dni gospodarstwa licza sie z uplywu czasu, takze offline.
	var day_seconds := float(GameData.balance().get("day", {}).get("seconds", 600.0))
	var clock := _fresh_state(["leghorn"], 10000.0)
	Simulation.advance(clock, day_seconds * 2.0)
	_check(clock.days == 2, "po dwoch dlugosciach dnia licznik dni pokazuje 2")


## Glod: po okresie laski kury padaja i zostawiaja zwloki, ktore sie rozkladaja.
func _test_hunger() -> void:
	var hunger: Dictionary = GameData.balance().get("hunger", {})
	var grace := float(hunger.get("grace_minutes", 3.0)) * 60.0

	var state := _fresh_state(["leghorn", "leghorn", "leghorn"], 0.0)
	var short_result := Simulation.advance(state, grace * 0.5)
	_check(int(short_result["died_hunger"]) == 0, "w okresie laski zadna kura nie pada")
	_check(bool(short_result["out_of_feed"]), "brak paszy jest raportowany")
	_check(int(short_result["eggs_laid"]) == 0, "glodne kury nie znosza jaj")

	var starved := _fresh_state(["leghorn", "leghorn", "leghorn"], 0.0)
	var long_result := Simulation.advance(starved, grace + float(hunger.get("death_interval_seconds", 50.0)) * 2.5)
	_check(int(long_result["died_hunger"]) > 0, "po okresie laski kury zaczynaja padac")
	_check(starved.corpses.size() + int(long_result["rotted"]) == int(long_result["died_hunger"]),
			"po kazdej kurze zostaja zwloki")
	var run := Simulation.run_area()
	var inside := true
	for corpse: Corpse in starved.corpses:
		inside = inside and run.has_point(corpse.position())
	_check(inside, "zwloki leza na wybiegu, a nie poza nim")

	# Nakarmienie zeruje licznik glodu.
	starved.feed = 50.0
	Simulation.advance(starved, 1.0)
	_check(is_zero_approx(starved.hunger_seconds), "nakarmione stado przestaje glodowac")

	# Zwloki znikaja po czasie rozkladu.
	var rotting := _fresh_state(["leghorn"], 100.0)
	rotting.corpses.append(Corpse.create("leghorn", run.get_center()))
	var total := rotting.corpses[0].total_seconds()
	Simulation.advance(rotting, total * 0.5)
	_check(rotting.corpses.size() == 1, "w polowie rozkladu zwloki jeszcze leza")
	_check(rotting.corpses[0].progress() > 0.3, "postep rozkladu rosnie")
	Simulation.advance(rotting, total * 0.6)
	_check(rotting.corpses.is_empty(), "po czasie rozkladu zwloki znikaja")

	# Przy nadrabianiu czasu stado nie moze wyginac do zera.
	var away: Array[String] = []
	for i in 10:
		away.append("leghorn")
	var offline := _fresh_state(away, 0.0)
	# Lis w tle nie ma bezpiecznika (12.21) - tu mierzymy sam glod.
	var lis := _snapshot_event("fox")
	_never_event("fox")
	Simulation.advance(offline, 24.0 * 3600.0, true)
	_restore_event("fox", lis)
	_check(offline.hen_count() > 0, "po dlugiej przerwie bez paszy stado nie ginie w calosci")
	_check(offline.hen_count() >= 5, "bezpiecznik offline zostawia polowe stada")
	Game.new_game()


## Choroby (12.20): ogniska. Chora nie znosi i pada po death_minutes minutach
## REALNYCH; wybuch zaraza 30-100% stada po jednej kurze co minute; leku nie
## ma; szczepionka chroni tylko zdrowe; po ognisku 3-12 godzin spokoju.
func _test_disease() -> void:
	var backup := _snapshot_event("disease")
	var fox_backup := _snapshot_event("fox")
	_never_event("fox")
	var disease: Dictionary = GameData.balance().get("disease", {})
	var scale := GameData.time_scale()
	var death_real := float(disease.get("death_minutes", 5.0)) * 60.0

	var sick := _fresh_state(["cemani"], 100.0)
	sick.chickens[0].sick = true
	var before := sick.eggs_on_ground.size()
	Simulation.advance(sick, 60.0)
	_check(sick.eggs_on_ground.size() == before, "chora kura nie znosi jaj")
	_check(sick.chickens[0].progress() == 0.0, "postep jajka chorej kury stoi na zerze")

	# Smierc liczona zegarkiem: tuz przed czasem zyje, po czasie pada.
	var dying := _fresh_state(["leghorn"], 100.0)
	dying.chickens[0].sick = true
	var early := Simulation.advance(dying, (death_real - 10.0) * scale)
	_check(int(early["died_disease"]) == 0, "chora zyje jeszcze chwile przed czasem")
	var result := Simulation.advance(dying, 15.0 * scale)
	_check(int(result["died_disease"]) == 1, "chora kura pada po death_minutes minutach realnych")
	_check(dying.chickens.is_empty() and dying.corpses.size() == 1, "po chorej kurze zostaja zwloki")
	_check(float(disease.get("death_minutes", 0.0)) <= 6.0, "choroba zabija w kilka minut, nie w kwadrans")

	# Krzywa szansy: do 10 ptakow zero, potem rosnie ze stadem.
	_check(FarmState.disease_rate_per_hour(5) == 0.0, "stado 5: zero szansy")
	_check(FarmState.disease_rate_per_hour(10) == 0.0, "stado 10: zero szansy")
	var r20 := FarmState.disease_rate_per_hour(20)
	var r50 := FarmState.disease_rate_per_hour(50)
	var r100 := FarmState.disease_rate_per_hour(100)
	_check(r20 > 0.0 and r20 <= 0.1, "stado 20: niska szansa (%.3f/h)" % r20)
	_check(r50 >= 0.3, "stado 50: czesta choroba (%.2f/h)" % r50)
	_check(r100 > r50 and r100 >= 1.0, "stado 100: bardzo czesta (%.2f/h)" % r100)
	_check(is_equal_approx(FarmState.disease_rate_per_hour(400), r100), "powyzej 100 plasko")
	_check(FarmState.disease_rate_per_hour(15) > 0.0 and FarmState.disease_rate_per_hour(15) < r20,
			"miedzy punktami liniowo")

	# 12.22 (wlasciciel 25.11): ognisko bierze JEDNA rase, zaraza wszystkie
	# jej niezaszczepione ptaki, inne rasy sa odporne.
	var mix := _fresh_state([], 10000000.0)
	for i in 12:
		mix.chickens.append(Chicken.create("leghorn"))
	for i in 7:
		mix.chickens.append(Chicken.create("rhode"))
	var picked := {}
	for i in 200:
		var trial := _fresh_state([], 1.0)
		for hen: Chicken in mix.chickens:
			trial.chickens.append(Chicken.create(hen.breed_id))
		var out := _empty_out()
		Simulation._start_outbreak(trial, out, 1 << 30)
		var rasa := String(out.get("outbreak_breed", ""))
		picked[rasa] = true
		var ile := 12 if rasa == "leghorn" else 7
		if int(out.get("outbreak", 0)) != ile or trial.outbreak_breed != rasa:
			_check(false, "ognisko %s planuje %d zarazen (jest %d)" % [rasa, ile, int(out.get("outbreak", 0))])
			break
	_check(picked.has("leghorn") and picked.has("rhode") and picked.size() == 2,
			"ognisko losuje jedna z ras na fermie (%s)" % str(picked.keys()))

	# Przezywalnosc: losowana przy wybuchu, 0%, 10%, 20% albo 30%.
	var szanse := {}
	var zle := 0
	for i in 300:
		var herd := _herd(15)
		Simulation._start_outbreak(herd, _empty_out(), 1 << 30)
		var p := int(round(herd.outbreak_survive * 100.0))
		szanse[p] = true
		if not p in [0, 10, 20, 30]:
			zle += 1
	_check(zle == 0 and szanse.has(0) and szanse.has(30), "przezywa 0-30%% chorych, co 10%% (%s)" % str(szanse.keys()))

	# Przebieg ogniska: pierwsza od razu, potem jedna na minute. 40 leghornow
	# choruje, 60 zaszczepionych rhode jest bezpiecznych; nikt nie przezywa.
	disease["rate_per_hour"] = [[0, 100000.0]]
	disease["survive_share_min"] = 0.0
	disease["survive_share_max"] = 0.0
	var farm := _herd(40)
	for i in 60:
		var odporna := Chicken.create("rhode")
		odporna.vaccinated = true
		farm.chickens.append(odporna)
	_past_grace(farm)
	# 90 s zamiast 60: kostka rzuca co pelne 60 s zegara, a krok 1 s gry to
	# 3 s zegara z bledem zaokraglen — rowne 60 bywa 59,9999.
	var start := Simulation.advance(farm, 90.0 * scale)
	_check(int(start.get("outbreak", 0)) == 40, "wybuch zaplanowal 40 zarazen (cala rasa)")
	_check(farm.outbreak_on and farm.outbreak_breed == "leghorn", "ognisko trwa, rasa leghorn")
	var sick_now := farm.sick_count()
	_check(sick_now >= 1 and sick_now <= 2, "na starcie choruje jedna, najwyzej dwie (%d)" % sick_now)
	Simulation.advance(farm, 180.0 * scale)
	_check(farm.sick_count() == sick_now + 3, "trzy minuty pozniej o trzy chore wiecej (%d)" % farm.sick_count())
	# Pare godzin: ognisko wygasa po dokladnie 40 stratach.
	var dead := 0
	var over := 0
	var over_dead := -1
	var new_outbreaks := 0
	for i in 120:
		var step := Simulation.advance(farm, 60.0 * scale)
		dead += int(step["died_disease"])
		new_outbreaks += 1 if int(step.get("outbreak", 0)) > 0 else 0
		if int(step.get("outbreak_over", 0)) > 0:
			over += 1
			over_dead = int(step.get("outbreak_dead", -1))
	_check(dead == 40, "ognisko zabilo dokladnie 40 kur (%d)" % dead)
	_check(farm.hen_count() == 60 and farm.hens_of_breed("rhode") == 60, "inna rasa nietknieta (%d)" % farm.hen_count())
	_check(over == 1 and over_dead == 40, "koniec ogniska zgloszony raz, z bilansem 40")
	_check(not farm.outbreak_on and farm.sick_count() == 0, "po ognisku nikt nie choruje")
	_check(new_outbreaks == 0, "w czasie spokoju nie wybucha nowe ognisko")
	var calm_h := farm.disease_calm / 3600.0
	_check(calm_h > 0.0 and calm_h <= float(disease.get("calm_hours_max", 12.0)),
			"po ognisku spokoj (zostalo %.1f h)" % calm_h)
	# Koniec spokoju: przy szansie 100000/h kolejne ognisko wybucha od razu.
	for i in 10:
		farm.chickens.append(Chicken.create("marans"))
	Simulation.advance(farm, (farm.disease_calm + 120.0) * scale)
	_check(farm.outbreak_on or farm.sick_count() > 0 or farm.hen_count() < 70,
			"po spokoju choroba wraca")

	# Ozdrowiency: przy 30% czesc chorych wstaje, reszta pada, wszyscy z tej
	# rasy przechodza chorobe, a ozdrowiali sa juz odporni.
	disease["survive_share_min"] = 0.3
	disease["survive_share_max"] = 0.3
	var ozdrowiency := _herd(200)
	_past_grace(ozdrowiency)
	var padly := 0
	var wstaly := 0
	var bilans := -1
	for i in 260:
		var step := Simulation.advance(ozdrowiency, 60.0 * scale)
		padly += int(step["died_disease"])
		wstaly += int(step.get("recovered", 0))
		if int(step.get("outbreak_over", 0)) > 0:
			bilans = int(step.get("outbreak_saved", -1))
			break
	_check(padly + wstaly == 200, "cala rasa przeszla chorobe (padlo %d, wyzdrowialo %d)" % [padly, wstaly])
	_check(wstaly >= 35 and wstaly <= 85, "przezylo okolo 30%% (%d z 200)" % wstaly)
	_check(bilans == wstaly, "koniec ogniska podaje liczbe ozdrowialych")
	var odporne := 0
	for hen: Chicken in ozdrowiency.chickens:
		if hen.vaccinated and not hen.sick:
			odporne += 1
	_check(odporne == wstaly, "ozdrowiale sa odporne (%d)" % odporne)
	disease["survive_share_min"] = 0.0
	disease["survive_share_max"] = 0.0

	# Spokoj trwa od calm_hours_min do calm_hours_max.
	var low := float(disease.get("calm_hours_min", 3.0)) * 3600.0
	var high := float(disease.get("calm_hours_max", 12.0)) * 3600.0
	var calm_bad := 0
	for i in 50:
		var x := _herd(20)
		x.outbreak_on = true
		Simulation._end_outbreak(x, _empty_out())
		if x.disease_calm < low or x.disease_calm > high:
			calm_bad += 1
	_check(calm_bad == 0 and low >= 3.0 * 3600.0 and high <= 12.0 * 3600.0, "spokoj 3-12 godzin")

	# Szczepienie: zaszczepione nie lapia, ognisko gasnie, gdy brak kogo zarazic.
	var vax := _herd(100)
	_past_grace(vax)
	for i in 60:
		vax.chickens[i].vaccinated = true
	var vax_dead := 0
	for i in 90:
		vax_dead += int(Simulation.advance(vax, 60.0 * scale)["died_disease"])
	var vax_sick := 0
	for hen: Chicken in vax.chickens:
		if hen.vaccinated and hen.sick:
			vax_sick += 1
	_check(vax_sick == 0, "zaszczepiona kura nie choruje")
	_check(vax_dead == 40, "przy 100%% padaja tylko niezaszczepione (%d z 40)" % vax_dead)
	_check(vax.hen_count() == 60, "zaszczepione przezyly (%d)" % vax.hen_count())

	# Cale stado zaszczepione: kostka nie ma kogo zarazic.
	var all_vax := _herd(50)
	_past_grace(all_vax)
	for hen: Chicken in all_vax.chickens:
		hen.vaccinated = true
	var none := Simulation.advance(all_vax, 3600.0 * scale)
	_check(int(none.get("outbreak", 0)) == 0 and not all_vax.outbreak_on, "w pelni zaszczepione stado nie choruje")

	# Karencja: mloda farma nie choruje mimo pewnej kostki.
	var young := _herd(100)
	var quiet := Simulation.advance(young, 600.0 * scale)
	_check(int(quiet["got_sick"]) == 0, "w okresie ochronnym nikt nie choruje")

	# Gra w tle: bezpiecznik strat (polowa stada) dziala tez na ognisko.
	var away := _herd(100)
	_past_grace(away)
	var away_out := Simulation.advance(away, 3.0 * 3600.0 * scale, true)
	var away_loss := int(away_out["died_disease"])
	_check(away_loss > 0 and away_loss <= 50, "w tle ognisko zabija najwyzej polowe (%d)" % away_loss)
	_restore_event("disease", backup)

	# Domyslna krzywa: stado 10 nie choruje przez dobe.
	var small := _herd(10)
	_past_grace(small)
	var small_out := Simulation.advance(small, 24.0 * 3600.0 * scale, true)
	_check(int(small_out["got_sick"]) == 0, "stado do 10 ptakow nie choruje wcale")

	# Domyslna krzywa: stado 100 bez szczepien choruje w ciagu doby.
	var big := _herd(100)
	_past_grace(big)
	var big_sick := 0
	for i in 24:
		big_sick += int(Simulation.advance(big, 3600.0 * scale)["got_sick"])
	_check(big_sick > 0, "stado 100 bez szczepien choruje w ciagu doby")

	# Zapis przenosi ognisko i spokoj.
	var saved := _herd(30)
	saved.outbreak_on = true
	saved.outbreak_left = 7
	saved.outbreak_timer = 12.5
	saved.outbreak_dead = 3
	saved.disease_calm = 999.0
	var back: FarmState = SaveGame.from_dict(SaveGame.to_dict(saved))["state"]
	_check(back.outbreak_on and back.outbreak_left == 7 and back.outbreak_dead == 3
			and is_equal_approx(back.outbreak_timer, 12.5) and is_equal_approx(back.disease_calm, 999.0),
			"ognisko i spokoj przezywaja zapis")
	var old_save := SaveGame.to_dict(_herd(3))
	for key: String in ["outbreak_on", "outbreak_left", "outbreak_timer", "outbreak_dead", "disease_calm"]:
		old_save.erase(key)
	var old_back: FarmState = SaveGame.from_dict(old_save)["state"]
	_check(not old_back.outbreak_on and old_back.disease_calm == 0.0, "stary zapis bez ogniska wczytuje sie")

	_restore_event("disease", backup)
	_restore_event("fox", fox_backup)
	Game.new_game()


## Stado `count` leghornow z zapasem paszy na dlugo.
func _herd(count: int) -> FarmState:
	var hens: Array[String] = []
	for i in count:
		hens.append("leghorn")
	return _fresh_state(hens, 10000000.0)


## Przesuwa wiek farmy za karencje zdarzen (pol godziny zegarka z zapasem).
func _past_grace(state: FarmState) -> void:
	state.days = int(3600.0 * GameData.time_scale() / 600.0) + 2


func _empty_out() -> Dictionary:
	return {"died_hunger": 0, "died_disease": 0, "fox_took": 0, "got_sick": 0}


## Lis: przychodzi, daje graczowi chwile na reakcje i dopiero potem zabiera
## czesc stada — nigdy calosci.
func _test_fox() -> void:
	var fox: Dictionary = GameData.balance().get("fox", {})
	var hens: Array[String] = []
	for i in 20:
		hens.append("leghorn")

	# Karencja: przez pierwsze pol godziny gry lis nie przychodzi wcale.
	var young := _fresh_state(hens, 100000.0)
	_check(young.played_seconds() < float(fox.get("grace_minutes", 30)) * 60.0,
			"nowa farma jest jeszcze w okresie ochronnym")
	var quiet := Simulation.advance(young, 600.0)
	_check(int(quiet["fox_arrived"]) == 0 and int(quiet["fox_blocked"]) == 0,
			"w okresie ochronnym lis nie podchodzi ani razu")

	# Male stado lis zostawia w spokoju nawet po karencji.
	var tiny := _fresh_state(["leghorn", "leghorn"], 100.0)
	_arm_fox(tiny)
	var tiny_result := Simulation.advance(tiny, 5.0)
	_check(int(tiny_result["fox_arrived"]) == 0, "przy malym stadzie lis nie przychodzi")
	_check(tiny.hen_count() == 2, "male stado zostaje nietkniete")

	# Wejscie: lis od razu porywa pierwsza kure i zostaje na wybiegu.
	var state := _fresh_state(hens, 100000.0)
	_arm_fox(state)
	# Zwloki zostaja z szansa carcass_share (0,5) na kazda zabita kure. Przy
	# trzech ofiarach raz na osiem przebiegow nie zostawalo nic i test
	# "migal". Tu chcemy pewnosci, wiec szansa 100%; wraca na koncu testu.
	var fox_cfg: Dictionary = GameData.balance()["fox"]
	var stary_udzial: float = float(fox_cfg.get("carcass_share", 0.5))
	fox_cfg["carcass_share"] = 1.0
	var arrival := Simulation.advance(state, 1.0)
	_check(int(arrival["fox_arrived"]) == 1, "lis przychodzi, gdy kostka padnie")
	_check(int(arrival["fox_took"]) >= 1, "pierwsza kura ginie zaraz po wejsciu")
	_check(state.fox_visit_left > 0.0, "wizyta trwa dalej")
	_check(state.fox_kill_left >= 1, "lis ma jeszcze lup do wziecia")
	_check(state.fox_taps_left == int(fox.get("scare_taps", 20)),
			"gracz dostaje pelna pule trafien")

	# Lup lisa to STALA liczba kur z przedzialu kills_min..kills_max,
	# a nie procent stada — wlasciciel chcial "zabije pare sztuk i pojdzie".
	var limit := int(arrival["fox_took"]) + state.fox_kill_left
	_check(limit >= int(fox.get("kills_min", 3)),
			"lup nie mniejszy niz minimum (%d)" % limit)
	_check(limit <= int(fox.get("kills_max", 10)),
			"lup nie wiekszy niz maksimum (%d)" % limit)

	# Lis zabija STOPNIOWO, co kilka sekund jedna kure — a nie wszystkie naraz.
	# Krok dobieramy tak, zeby zmiescil sie miedzy dwoma zabojstwami.
	var krok := float(fox.get("kill_interval_max", 10.0)) * GameData.time_scale()
	var w_trakcie := Simulation.advance(state, krok)
	_check(int(w_trakcie["fox_took"]) > 0, "w trakcie wizyty gina kolejne kury")
	_check(int(w_trakcie["fox_took"]) <= 2,
			"ale po jednej, nie hurtem (%d w %ds)" % [int(w_trakcie["fox_took"]), int(krok)])
	_check(state.hen_count() > 20 - limit - 1, "nie wszystkie od razu — zabija po kolei")

	# Koniec czasu konczy wizyte i czysci caly stan lisa.
	Simulation.advance(state, state.fox_visit_left * GameData.time_scale() + 1.0)
	_check(state.fox_visit_left <= 0.0, "po swoim czasie lis odchodzi")
	_check(state.fox_kill_left == 0 and state.fox_taps_left == 0,
			"stan lisa wyczyszczony do zera")

	# Po napasci zostaja slady na wybiegu.
	_check(state.corpses.size() > 0, "po napasci zostaja zwloki na wybiegu")
	fox_cfg["carcass_share"] = stary_udzial

	# Trzy lisy naraz nie moga sie zdarzyc: dopoki jeden jest na wybiegu,
	# zaden drugi nie wejdzie. To jest blad, z ktorym zyl wlasciciel.
	var busy := _fresh_state(hens, 100000.0)
	_arm_fox(busy)
	Simulation.advance(busy, 1.0)
	var przyjscia := 0
	for i in 200:
		przyjscia += int(Simulation.advance(busy, 5.0)["fox_arrived"])
		if busy.fox_visit_left <= 0.0:
			break
	_check(przyjscia == 0, "drugi lis nie wchodzi, gdy pierwszy jeszcze jest")

	# Przeganianie palcem: dopiero ostatnie trafienie wyprasza lisa.
	Game.new_game()
	for i in 20:
		Game.state.chickens.append(Chicken.create("leghorn"))
	_arm_fox(Game.state)
	Simulation.advance(Game.state, 1.0)
	_check(Game.state.fox_visit_left > 0.0, "lis na wybiegu przed przeganianiem")
	var trafienia := int(fox.get("scare_taps", 20))
	for i in trafienia - 1:
		_check(not Game.poke_fox(), "trafienie %d jeszcze nie wyprasza" % (i + 1))
	_check(Game.poke_fox(), "ostatnie trafienie przegania lisa")
	_check(Game.state.fox_visit_left <= 0.0, "po przegonieniu lisa nie ma")
	_check(Game.state.fox_hand_scared, "gra pamieta, ze przegonil go golymi rekami")
	_check(not Game.poke_fox(), "bez lisa nie ma kogo przeganiac")
	_disarm_fox()


## Ustawia stan tak, zeby lis wszedl przy najblizszym kroku: po karencji,
## z pelnym licznikiem do losowania, bez plotu i z kostka ustawiona na pewniak.
## Kostka siedzi we WSPOLNYM slowniku balansu, wiec po tescie trzeba oddac
## stan przez `_disarm_fox()`.
var _fox_backup: Dictionary = {}

func _arm_fox(state: FarmState) -> void:
	if _fox_backup.is_empty():
		_fox_backup = _snapshot_event("fox")
	var fox: Dictionary = GameData.balance().get("fox", {})
	fox["chance"] = 1.0
	# Rzez ma wlasny test (_test_fox_massacre); tu lis bierze zwykly lup.
	fox["massacre_chance"] = 0.0
	# Bez fazy w krzakach: stare testy sprawdzaja wejscie w tym samym kroku.
	# Czajenie sie i podchodzenie pod plot ma wlasny test (_test_fox_lurk).
	fox["lurk_min_seconds"] = 0.0
	fox["lurk_max_seconds"] = 0.0
	fox["approach_seconds"] = 0.0
	# Pol godziny ZEGARKA to tyle sekund gry razy skala czasu.
	var grace_game := float(_fox_backup.get("grace_minutes", 30.0)) * 60.0 * GameData.time_scale()
	state.days = int(grace_game / 600.0) + 2
	state.guard_level = 0
	state.fox_roll_timer = 1000000.0


func _disarm_fox() -> void:
	if _fox_backup.is_empty():
		return
	_restore_event("fox", _fox_backup)
	_fox_backup = {}


## Lis przegoniony golymi rekami wraca szybciej — chyba ze gospodarstwo ma
## psa albo plot. Sprawdzamy sam odstep miedzy losowaniami, bo to on decyduje.
func _test_fox_return_speed() -> void:
	var fox: Dictionary = GameData.balance().get("fox", {})
	var odstep := float(fox.get("roll_minutes", 60.0)) * 60.0
	var kara := float(fox.get("hand_return_factor", 0.1))
	_check(kara < 1.0, "kara za reczne przegonienie skraca odstep")

	var hens: Array[String] = []
	for i in 20:
		hens.append("leghorn")

	# Bez psa i plotu: po recznym przegonieniu lis ma szanse wrocic juz po
	# dziesiatej czesci zwyklego odstepu.
	var goly := _fresh_state(hens, 0.0)
	_arm_fox(goly)
	goly.fox_hand_scared = true
	goly.fox_roll_timer = odstep * kara + 1.0
	var wrocil := 0
	for i in 60:
		var kopia := _fresh_state(hens, 0.0)
		_arm_fox(kopia)
		kopia.fox_hand_scared = true
		kopia.fox_roll_timer = odstep * kara * 0.99
		wrocil += int(Simulation.advance(kopia, 60.0 * GameData.time_scale())["fox_arrived"])
	_check(wrocil > 0, "po recznym przegonieniu lis wraca duzo szybciej")

	# Z psem kara nie dziala: po skroconym odstepie lis jeszcze nie wraca.
	var z_psem := 0
	for i in 60:
		var kopia := _fresh_state(hens, 0.0)
		_arm_fox(kopia)
		kopia.dog_level = 1
		kopia.fox_hand_scared = true
		kopia.fox_roll_timer = odstep * kara * 0.99
		z_psem += int(Simulation.advance(kopia, 60.0 * GameData.time_scale())["fox_arrived"])
	_check(z_psem == 0, "pies zdejmuje kare za reczne przegonienie")
	_disarm_fox()



func _test_vet_and_selling() -> void:
	Game.new_game()
	Game.state.chickens.clear()
	Game.state.chickens.append(Chicken.create("leghorn"))
	Game.state.chickens.append(Chicken.create("cemani"))
	Game.state.chickens[0].sick = true
	Game.state.chickens[1].sick = true
	Game.state.money = 100000.0

	_check(Game.state.sick_count() == 2, "licznik chorych kur")
	# Leku nie ma (wlasciciel 25.11): ani w grze, ani w balansie.
	_check(not Game.has_method("buy_medicine") and not Game.has_method("medicine_price"),
			"w grze nie ma leku")
	_check(not (GameData.balance().get("disease", {}) as Dictionary).has("medicine_price"),
			"balans nie zna ceny leku")
	# Szczepionka nie leczy i nie liczy chorych do ceny.
	Game.state.chickens.append(Chicken.create("rhode"))
	_check(Game.state.unvaccinated_count() == 1, "do szczepienia liczy sie tylko zdrowa")
	var per_hen := float(GameData.balance()["disease"].get("vaccine_price_per_hen", 0))
	var base := float(GameData.balance()["disease"].get("vaccine_price", 0))
	_check(is_equal_approx(Game.vaccine_price(), base + per_hen), "cena szczepienia tylko za zdrowe")
	_check(Game.buy_vaccine(), "szczepienie da sie kupic")
	_check(Game.state.sick_count() == 2, "szczepionka nie leczy chorych")
	var sick_vaccinated := 0
	for hen: Chicken in Game.state.chickens:
		if hen.sick and hen.vaccinated:
			sick_vaccinated += 1
	_check(sick_vaccinated == 0, "chore nie dostaja szczepienia")
	_check(Game.state.vaccinated_count() == 1, "zaszczepiona jest tylko zdrowa")

	_check(FarmState.hen_sell_price("leghorn") < float(GameData.breed("leghorn").get("price", 0)),
			"sprzedaz jest tansza od zakupu")
	_check(is_zero_approx(FarmState.hen_sell_price("leghorn", true)),
			"chora kura nie ma ceny skupu")

	# Chorej sztuki skup nie przyjmuje: zostaje tylko McDonald.
	Game.state.chickens.clear()
	var ill := Chicken.create("rhode")
	ill.sick = true
	Game.state.chickens.append(ill)
	_check(Game.has_sick("rhode"), "w stadzie jest chora sztuka")
	_check(is_zero_approx(Game.sell_hen("rhode")), "chorej kury nie da sie sprzedac")
	_check(Game.state.chickens.size() == 1, "nieudana sprzedaz nie usuwa kury ze stada")

	var purse := Game.state.money
	Game.state.outbreak_on = true
	Game.state.outbreak_dead = 0
	_check(Game.cull_hen("rhode"), "chora kure da sie oddac do McDonalda")
	_check(Game.state.chickens.is_empty(), "oddana kura znika ze stada")
	_check(Game.state.outbreak_dead == 1, "ubita w ognisku liczy sie do strat ogniska")
	Game.state.outbreak_on = false
	_check(is_equal_approx(Game.state.money, purse + Game.mcdonalds_price()),
			"za chora kure jest kilka zlotych, a nie zero")
	var choroba_cfg: Dictionary = GameData.balance().get("disease", {})
	_check(is_equal_approx(Game.mcdonalds_price(), float(choroba_cfg.get("mcdonalds_price", -1))),
			"skup placi tyle, ile stoi w balance.json")
	_check(Game.mcdonalds_price() > 0.0, "skup placi wiecej niz zero")
	_check(not Game.cull_hen("rhode"), "nie ma juz czego ubijac")

	# Zdrowa idzie normalnie, za pelna stawke.
	Game.state.chickens.append(Chicken.create("rhode"))
	var full_price := Game.sell_hen("rhode")
	_check(is_equal_approx(full_price, FarmState.hen_sell_price("rhode")), "zdrowa idzie za pelna stawke")

	# Kogut tez: chorego nie sprzedasz, ale do McDonalda mozna.
	Game.state.chickens.clear()
	var sick_cock := Chicken.create_rooster("marans")
	sick_cock.sick = true
	Game.state.chickens.append(sick_cock)
	_check(is_zero_approx(Game.sell_hen("marans", true)), "chorego koguta tez nie kupia")
	_check(Game.cull_hen("marans", true), "chorego koguta da sie ubic")
	_check(Game.state.chickens.is_empty(), "ubity kogut znika ze stada")
	_check(is_zero_approx(Game.sell_hen("rhode")), "nie ma czego sprzedac")

	# Szczepienie obejmuje tylko kury zyjace w chwili szczepienia.
	Game.new_game()
	Game.state.money = 100000.0
	var unvaccinated_before := Game.state.unvaccinated_count()
	_check(unvaccinated_before == Game.state.hen_count(), "na starcie nikt nie jest zaszczepiony")
	_check(Game.buy_vaccine(), "szczepienie da sie kupic")
	_check(Game.state.unvaccinated_count() == 0, "po szczepieniu cale stado jest chronione")
	Game.state.chickens.append(Chicken.create("leghorn"))
	_check(Game.state.unvaccinated_count() == 1, "nowa kura nie dziedziczy szczepienia")
	Game.new_game()


## Rozbudowa inkubatora zwieksza liczbe miejsc i przezywa zapis.
func _test_incubator_upgrade() -> void:
	Game.new_game()
	var base := Game.incubator_slots()
	var upgrade := Game.state.next_incubator_upgrade()
	_check(not upgrade.is_empty(), "inkubator ma co rozbudowywac")

	Game.state.money = 0.0
	_check(not Game.upgrade_incubator(), "bez pieniedzy nie ma rozbudowy")
	Game.state.money = float(upgrade.get("price", 0))
	_check(Game.upgrade_incubator(), "rozbudowa udaje sie przy pelnej kwocie")
	_check(Game.incubator_slots() == base, "w trakcie budowy inkubator ma stare miejsca")
	_finish_build(Game.state, "incubator")
	_check(Game.incubator_slots() > base, "po rozbudowie miejsc jest wiecej")
	_check(Game.incubator_slots() == int(upgrade.get("slots", 0)), "liczba miejsc zgodna z balance.json")

	SaveGame.save_state(Game.state)
	var loaded := SaveGame.load_state()
	_check(not loaded.is_empty() and (loaded["state"] as FarmState).incubator_slots() == Game.incubator_slots(),
			"poziom inkubatora przezywa zapis")
	SaveGame.clear()
	Game.new_game()


## Wygrana: milion zlotych albo pelna kolekcja ras.
func _test_win() -> void:
	var goal := float(GameData.balance().get("win", {}).get("money", 0))
	_check(goal > 0.0, "warunek wygranej jest ustawiony")

	var rich := _fresh_state(["leghorn"], 100.0)
	rich.money = goal - 1.0
	_check(Simulation.check_win(rich) == "", "ponizej progu gra trwa")
	rich.money = goal
	_check(Simulation.check_win(rich) == "money", "milion konczy gre")
	_check(rich.won, "stan pamieta wygrana")
	_check(Simulation.check_win(rich) == "", "wygrana zglasza sie tylko raz")

	# Kolekcja ras nie konczy juz gry: bez progow odblokowania da sie kupic
	# po jednej sztuce kazdej rasy w niecale szesc godzin.
	var collector := _fresh_state(["leghorn"], 100.0)
	collector.chickens.clear()
	for breed: Dictionary in GameData.breeds():
		collector.chickens.append(Chicken.create(String(breed.get("id", ""))))
	_check(collector.has_full_collection(), "komplet ras rozpoznany")
	_check(Simulation.check_win(collector) == "", "sama kolekcja nie konczy gry")

	var partial := _fresh_state(["leghorn"], 100.0)
	_check(not partial.has_full_collection(), "jedna rasa to nie kolekcja")
	_check(Simulation.check_win(partial) == "", "bez pieniedzy gra trwa")

	# Wygrana przezywa zapis, zeby okno nie wyskakiwalo po kazdym wczytaniu.
	SaveGame.save_state(rich)
	var loaded := SaveGame.load_state()
	_check(not loaded.is_empty() and (loaded["state"] as FarmState).won, "wygrana przezywa zapis")
	SaveGame.clear()
	Game.new_game()


## Kwoty: pelne zlotowki bez przecinka, separator tysiecy, grosze tylko
## przy drobnych kwotach w rodzaju wartosci jajka.
func _test_money_format() -> void:
	_check(NumberFormat.money(0.0) == "0 zł", "0 zl")
	_check(NumberFormat.money(1.0) == "1 zł", "pelna zlotowka")
	_check(NumberFormat.money(1000000.0) == "1\u00a0000\u00a0000 zł", "milion z separatorami")
	_check(NumberFormat.amount_only(3.0) == "3", "kwota bez waluty")

	# Zadnych przecinkow w kwotach: licznik na pasku ma pokazywac pelne
	# zlotowki, a nie "298,27". Zaokraglenie w dol, zeby nigdy nie obiecac
	# wiecej, niz gracz ma na koncie.
	for amount in [0.4, 12.5, 298.27, 0.999, 2.004]:
		_check(not NumberFormat.money(amount).contains(","),
				"kwota %.3f bez przecinka (%s)" % [amount, NumberFormat.money(amount)])
	_check(NumberFormat.money(12.9) == "12 zł", "zaokraglenie w dol, nie w gore")
	_check(NumberFormat.money(298.27) == "298 zł", "kwota z paska bez groszy")

	# Drobne kwoty mimo to musza byc czytelne: jajko za 40 groszy nie moze
	# pokazywac sie jako "0 zl", bo rasa wygladalaby na bezwartosciowa.
	_check(NumberFormat.small_money(0.4) == "40 gr", "wartosc jajka w groszach")
	_check(NumberFormat.small_money(1.0) == "1 zł", "rowna zlotowka to zlotowka")
	_check(NumberFormat.small_money(0.01) == "1 gr", "jeden grosz")
	for breed: Dictionary in GameData.breeds():
		var shown := NumberFormat.small_money(float(breed.get("egg_value", 0.0)))
		_check(shown != "0 gr" and shown != "0 zł",
				"jajko rasy %s ma widoczna wartosc (%s)" % [breed.get("id", ""), shown])

	# Ceny jaj musza siedziec w widelkach, ktore ustalilismy dla balansu.
	# Od 12.15 wlasciciel sam stroi ceny w balance.json/breeds.json, a GitHub
	# buduje gre po kazdym commicie. Test nie trzyma juz konkretnych cen,
	# tylko granice rozsadku: jajko kosztuje cokolwiek i nie wiecej niz kura.
	# (Zasada dla Claude'a "nie ruszac cen bez polecenia" stoi w
	# PROJECT_STATE.md, nie tutaj.)
	for breed: Dictionary in GameData.breeds():
		var value := float(breed.get("egg_value", 0))
		_check(value > 0.0 and value < float(breed.get("price", 0)),
				"jajko rasy '%s' kosztuje wiecej niz 0 i mniej niz kura" % breed.get("id", ""))

	# Zwyczajowo sell_price to 70% price, ale to pole stroi sie recznie.
	# Pilnujemy tylko, zeby kupno-sprzedaz nie dawalo darmowych pieniedzy.
	for breed: Dictionary in GameData.breeds():
		var sell := float(breed.get("sell_price", 0))
		_check(sell > 0.0 and sell < float(breed.get("price", 0)),
				"sprzedaz kury rasy '%s' wiecej niz 0 i mniej niz kupno" % breed.get("id", ""))


## Pod nieobecnosc gracza jaja omijaja wybieg i ida prosto do magazynu.
## Gospodarstwo bez paszy. Dziura znaleziona przez znajomego wlasciciela:
## "jak zrobisz kury, to nie musisz ich karmic nigdy" — inkubator i odchow
## chodzily przy pustym magazynie, wiec stado odnawialo sie szybciej, niz
## gloddzilo, a przy stalym odstepie zgonow duze stado padalo godzinami.
func _test_starving_farm() -> void:
	var hens: Array[String] = []
	for i in 40:
		hens.append("leghorn")

	# Bez paszy nic sie nie wykluwa i nic nie rosnie.
	var starving := _laying_state(hens, 0.0)
	starving.days = 10
	starving.coop_level = 3
	for bird: Chicken in starving.chickens:
		bird.vaccinated = true
	for i in 6:
		starving.chicks.append(Chick.create("leghorn"))
	for i in 4:
		starving.incubating.append(EggBatch.create("leghorn", 1))
	var chicks_before := starving.chicks.size()
	var batches_before := starving.incubating.size()
	# Cztery minuty: trzy minuty karencji i minuta padania. Dluzej i cale stado
	# by wymarlo, a potrzebne jest zywe do sprawdzenia, czy po dosypaniu paszy
	# gospodarstwo rusza z miejsca.
	var hungry := Simulation.advance(starving, 240.0)
	_check(int(hungry["eggs_laid"]) == 0, "glodne stado nie znosi jaj")
	_check(int(hungry["hatched"]) == 0 and starving.incubating.size() == batches_before,
			"bez paszy inkubator stoi")
	_check(int(hungry["grown_up"]) == 0, "bez paszy pisklęta nie dorastaja")
	_check(starving.chicks.size() == chicks_before, "pisklęta czekaja, zadne nie dorosło")
	_check(int(hungry["died_hunger"]) > 0, "glodne stado zaczyna padac")

	# Tempo padania rosnie razem ze stadem.
	var small := _fresh_state(["leghorn", "leghorn", "leghorn", "leghorn", "leghorn"], 0.0)
	small.coop_level = 3
	var big_hens: Array[String] = []
	for i in 100:
		big_hens.append("leghorn")
	var big := _fresh_state(big_hens, 0.0)
	big.coop_level = 3
	var small_dead := int(Simulation.advance(small, 600.0)["died_hunger"])
	var big_dead := int(Simulation.advance(big, 600.0)["died_hunger"])
	_check(big_dead > small_dead * 3,
			"duze stado pada szybciej: %d zgonow na 100 kur wobec %d na 5" % [big_dead, small_dead])

	# Po dosypaniu paszy wszystko rusza z miejsca. Kogut tez gloduje i mogl
	# paść razem z kurami, a bez niego stado i tak by nie zniosło — wiec
	# upewniamy sie, ze jakis jest.
	starving.feed = 100000.0
	if not starving.has_rooster("leghorn"):
		starving.chickens.append(Chicken.create_rooster("leghorn"))
	_check(starving.laying_hen_count() > 0, "cos ze stada przezylo glodowke")
	var fed := Simulation.advance(starving, 600.0)
	_check(int(fed["eggs_laid"]) > 0, "po dosypaniu paszy stado znowu niesie")
	_check(int(fed["grown_up"]) > 0 or int(fed["hatched"]) > 0,
			"po dosypaniu paszy odchow i inkubator ruszaja")
	Game.new_game()


## Zasady wspolne dla lisa i choroby, podane przez wlasciciela wprost:
## przez pierwsze pol godziny gry nic sie nie dzieje, przy stadzie mniejszym
## niz piec sztuk tez nie, a potem losowanie co minute z zadana srednia.

## Blad zglaszony przez Bartka: po sprzedaniu wszystkich kur danej rasy
## przyciski tej rasy wyszarzaly sie, choc jaja zostaly w magazynie. Jaja
## sa wlasnoscia gracza i wolno je wylec takze wtedy, gdy stado tej rasy
## zostalo wyprzedane do zera.
func _test_incubate_without_flock() -> void:
	Game.new_game()
	Game.state.money = 100000.0
	Game.state.chickens.clear()
	Game.state.eggs["leghorn"] = Game.eggs_per_chick()
	_check(not Game.state.owns_breed("leghorn"), "zadnej kury tej rasy na farmie")
	_check(Game.can_incubate("leghorn"), "same jaja wystarczaja do wylegu")
	_check(Game.incubate("leghorn"), "wyleg rusza bez stada tej rasy")
	_check(Game.state.incubating.size() == 1, "partia wlozona do inkubatora")
	_check(int(Game.state.eggs.get("leghorn", 0)) == 0, "jaja zuzyte na pisklę")

	# Bez jaj nadal nie ma z czego wylegac — to nie jest ten sam przypadek.
	_check(not Game.can_incubate("cemani"), "brak jaj rasy wciaz blokuje wyleg")


## Po nieudanej probie wczytania gra zostaje z wpisanym kodem. Druga proba
## tym samym kodem musi wiec ruszyc, a nie odbic sie od "to juz twoj kod" —
## inaczej jedna chwila bez sieci zamyka graczowi droge do wlasnej farmy.
func _test_retry_same_code() -> void:
	Game.new_game()
	# Kod spoza puli prawdziwych farm. Wczesniej stalo tu 327733 - kod
	# istniejacej farmy, ktora testy na GitHubie wczytywaly i nadpisywaly.
	var kod := "100001"
	Cloud.set_player_id(kod)
	_check(Cloud.player_id == kod, "urzadzenie ma juz ten kod")
	_check(Game.restore_from_code(kod), "ponowna proba tym samym kodem rusza")
	# Kod inny niz szesc cyfr nadal odpada od razu.
	_check(not Game.restore_from_code("12ab"), "zly kod odpada przed zapytaniem")


## Kod 8 z HTTPRequest to RESULT_BODY_DECOMPRESS_FAILED: serwer odpowiedzial,
## a Godot nie potrafil rozpakowac ciala. Rozpakowywanie jest teraz wylaczone
## po stronie Godota, ale gdyby gzip mimo wszystko do nas trafil, musimy sobie
## z nim poradzic sami, a nie udawac, ze serwera nie ma.
func _test_body_unpacking() -> void:
	var tekst := '[{"player_id":"100001","updated_at":1795000000}]'
	var czysty := tekst.to_utf8_buffer()
	_check(Cloud._body_text(czysty) == tekst, "zwykly JSON przechodzi bez zmian")

	var spakowany := czysty.compress(FileAccess.COMPRESSION_GZIP)
	_check(spakowany.size() >= 2 and spakowany[0] == 0x1f and spakowany[1] == 0x8b,
			"gzip zaczyna sie od 0x1f 0x8b")
	_check(Cloud._body_text(spakowany) == tekst, "gzip rozpakowany samodzielnie")

	_check(Cloud._body_text(PackedByteArray()) == "", "puste cialo nie wywraca gry")

	# Nazwa powodu dla kodu 8 ma byc po ludzku, a nie "nieznany powod".
	Cloud.last_action = "odczyt"
	Cloud.last_result = HTTPRequest.RESULT_BODY_DECOMPRESS_FAILED
	Cloud.last_http_code = 0
	var said := Cloud.describe_last()
	_check(said.contains("rozpakowa"), "kod 8 opisany po ludzku: %s" % said)
	_check(not said.contains(tr("DIAG_R_OTHER")), "kod 8 to juz nie 'nieznany powod'")


## Pies podworzowy — wprost z opisu wlasciciela: kupowany od razu, tanszy
## niz plot, goni lisa, ktory JUZ wszedl. Kundel po dluzszej chwili, owczarek
## od razu. Lis zawsze cos porwie; zero strat tylko wtedy, gdy gracz przegoni
## go palcem.
func _test_dog() -> void:
	var dogs: Array = GameData.balance().get("buildings", {}).get("dog", {}).get("upgrades", [])
	var fences: Array = GameData.balance().get("buildings", {}).get("guard", {}).get("upgrades", [])
	_check(dogs.size() == 2, "sa dwa psy do kupienia")
	_check(float(dogs[0].get("price", 0)) <= float(fences[0].get("price", 0)),
			"kundel nie drozszy niz najtanszy plot (%s wobec %s)"
			% [dogs[0].get("price"), fences[0].get("price")])
	# Liczby psow mozna stroic w balance.json. Test pilnuje tylko rozsadku:
	# szanse to prawdopodobienstwa, odstepy sa dodatnie, a owczarek - drozszy
	# pies - nie moze byc gorszy od kundla w zadnym parametrze.
	for d: Dictionary in dogs:
		var nazwa := String(d.get("name", "?"))
		_check(float(d.get("interval", 0.0)) > 0.0, "pies %s probuje co dodatnia liczbe sekund" % nazwa)
		_check(float(d.get("chance", -1.0)) > 0.0 and float(d.get("chance", 2.0)) <= 1.0,
				"szansa psa %s miedzy 0 a 1" % nazwa)
		_check(float(d.get("kill_chance", -1.0)) >= 0.0 and float(d.get("kill_chance", 2.0)) <= 1.0,
				"szansa zagryzienia psa %s miedzy 0 a 1" % nazwa)
		_check(float(d.get("price", 0)) > 0.0, "pies %s cos kosztuje" % nazwa)
	_check(float(dogs[1].get("interval", 99.0)) <= float(dogs[0].get("interval", 0.0)),
			"owczarek probuje nie rzadziej niz kundel")
	_check(float(dogs[1].get("chance", 0.0)) >= float(dogs[0].get("chance", 1.0)),
			"owczarek ma nie mniejsza szanse niz kundel")
	_check(float(dogs[1].get("kill_chance", 0.0)) >= float(dogs[0].get("kill_chance", 1.0)),
			"owczarek zagryza nie rzadziej niz kundel")
	_check(float(dogs[1].get("price", 0)) > float(dogs[0].get("price", 0)),
			"owczarek drozszy od kundla")

	# Pies kupowalny od poczatku, bez plotu jako warunku.
	Game.new_game()
	Game.state.money = float(dogs[0].get("price", 0))
	_check(Game.state.guard_level == 0, "zaczynamy bez plotu")
	_check(Game.upgrade_building("dog"), "psa kupuje sie bez kupowania plotu")
	_check(Game.state.dog_level == 1, "kundel na podworku")
	_check(Game.state.guard_level == 0, "zakup psa nie stawia plotu")

	# Czas wizyty i lup maleja z kazdym psem. Stado liczne, zeby lis mial
	# co zabierac i zeby roznica w lupie byla widoczna.
	var hens: Array[String] = []
	for i in 20:
		hens.append("leghorn")
	var bez := _fresh_state(hens, 0.0)
	var kundel := _fresh_state(hens, 0.0)
	kundel.dog_level = 1
	var owczarek := _fresh_state(hens, 0.0)
	owczarek.dog_level = 2
	_check(is_zero_approx(bez.dog_chance()), "bez psa nikt lisa nie goni")
	_check(owczarek.dog_chance() > kundel.dog_chance(), "owczarek skuteczniejszy od kundla")
	_check(owczarek.dog_interval() < kundel.dog_interval(), "owczarek probuje czesciej")
	_check(owczarek.dog_kill_chance() > 0.0 and is_zero_approx(kundel.dog_kill_chance()),
			"tylko owczarek zagryza lisa")

	# W symulacji: pies zmniejsza straty, ale ich nie zeruje.
	var straty_bez := 0
	var straty_z := 0
	var porwal_zawsze := true
	for i in 30:
		var a := _fresh_state(hens, 0.0)
		_arm_fox(a)
		straty_bez += _przezyj_wizyte(a)
		var b := _fresh_state(hens, 0.0)
		b.dog_level = 2
		_arm_fox(b)
		var zabral := _przezyj_wizyte(b)
		straty_z += zabral
		if zabral < 1:
			porwal_zawsze = false
	_check(straty_z < straty_bez, "z psem lis zabiera mniej (%d wobec %d)" % [straty_z, straty_bez])
	_check(straty_z > 0, "pies nie zeruje strat — lis zawsze cos porwie")
	_check(porwal_zawsze, "nawet przy owczarku lis bierze co najmniej jedna kure")
	_disarm_fox()


## Puszcza cala wizyte lisa i zwraca, ile kur zginelo.
func _przezyj_wizyte(state: FarmState) -> int:
	var zabral := int(Simulation.advance(state, 1.0)["fox_took"])
	var bezpiecznik := 0
	while state.fox_visit_left > 0.0 and bezpiecznik < 2000:
		zabral += int(Simulation.advance(state, 1.0)["fox_took"])
		bezpiecznik += 1
	return zabral


## Migracja zapisow 5 -> 6: stara jedna drabinka obrony rozbita na plot
## i psa. Nikt nie moze stracic tego, za co zaplacil.
func _test_guard_migration() -> void:
	var oczekiwane := {0: [0, 0], 1: [1, 0], 2: [1, 1], 3: [2, 1], 4: [2, 2], 5: [3, 2]}
	for stary: int in oczekiwane.keys():
		var stan := FarmState.new()
		stan.guard_level = stary
		var zapis := SaveGame.to_dict(stan)
		zapis["version"] = 5
		zapis.erase("dog_level")
		var wczytany: Dictionary = SaveGame.from_dict(zapis)
		_check(not wczytany.is_empty(), "stary zapis z obrona %d daje sie wczytac" % stary)
		if wczytany.is_empty():
			continue
		var odczyt: FarmState = wczytany["state"]
		var chciane: Array = oczekiwane[stary]
		var plot := odczyt.guard_level
		var pies := odczyt.dog_level
		_check(plot == chciane[0], "obrona %d -> plot %d (jest %d)" % [stary, chciane[0], plot])
		_check(pies == chciane[1], "obrona %d -> pies %d (jest %d)" % [stary, chciane[1], pies])


## 13.0: blokada inkubatora w trakcie rozbudowy, zycie psa, ferma admina.
func _test_v13_basics() -> void:
	var scale := GameData.time_scale()
	# Inkubator: przy jajach w srodku nie da sie rozbudowac; w trakcie
	# rozbudowy nic sie nie wykluwa i nie da sie wlozyc jaj.
	var st := _fresh_state(["leghorn", "leghorn"], 1000.0)
	st.add_egg("leghorn", 30)
	st.incubating.append(EggBatch.create("leghorn", 1))
	var old_state := Game.state
	Game.state = st
	st.money = 100000.0
	_check(not Game.upgrade_building("incubator") and not Game.upgrade_block_reason("incubator").is_empty(),
			"inkubatora z jajami nie da sie rozbudowac")
	st.incubating.clear()
	_check(Game.upgrade_building("incubator") and st.is_building("incubator"), "pusty inkubator sie rozbudowuje")
	_check(not Game.can_incubate("leghorn"), "w trakcie rozbudowy nie wklada sie jaj")
	var batch := EggBatch.create("leghorn", 1)
	st.incubating.append(batch)
	Simulation.advance(st, 60.0 * scale)
	_check(is_zero_approx(batch.elapsed), "w trakcie rozbudowy nic sie nie wykluwa")
	Game.state = old_state

	# Pies: zycie losowane z przedzialu, po nim pies umiera.
	var dogs: Array = GameData.balance()["buildings"]["dog"]["upgrades"]
	_check(is_equal_approx(float(dogs[0]["life_days_min"]), 12.0) and is_equal_approx(float(dogs[0]["life_days_max"]), 22.0)
			and is_equal_approx(float(dogs[1]["life_days_min"]), 4.0) and is_equal_approx(float(dogs[1]["life_days_max"]), 12.0),
			"kundel zyje 12-22 dni, owczarek 4-12")
	var poza := 0
	var suma := 0.0
	for i in 400:
		var d := FarmState.new()
		d.set_building_level("dog", 1)
		var dni := d.dog_life / 86400.0
		suma += dni
		if dni < 12.0 or dni > 22.0:
			poza += 1
	_check(poza == 0 and absf(suma / 400.0 - 17.0) < 0.6, "kundel: zycie w 12-22 dni, srednio ~17 (%.1f)" % (suma / 400.0))
	var pies := _fresh_state(["leghorn"], 100000.0)
	pies.set_building_level("dog", 2)
	_check(pies.dog_life >= 4.0 * 86400.0 and pies.dog_life <= 12.0 * 86400.0, "owczarek: zycie w 4-12 dni")
	pies.dog_age = pies.dog_life - 5.0
	var wynik := Simulation.advance(pies, 30.0 * scale)
	_check(pies.dog_level == 0 and int(wynik.get("dog_died", 0)) == 2, "po swoim czasie pies umiera")
	var zapis := SaveGame.from_dict(SaveGame.to_dict(_with_dog()))
	_check(zapis.has("state") and (zapis["state"] as FarmState).dog_life > 0.0, "zycie psa w zapisie")

	# Admin: tylko pod kodem 000000.
	_check(Game.ADMIN_CODE == "000000", "kod fermy admina 000000")
	var stary_kod := Cloud.player_id
	Cloud.player_id = "123456"
	_check(not Game.is_admin(), "zwykla ferma nie jest adminem")
	Cloud.player_id = "000000"
	_check(Game.is_admin(), "ferma 000000 jest adminem")
	var stary_stan := Game.state
	Game.state = _fresh_state(["leghorn"], 10.0)
	_check(Game.admin_change_level("incubator", 1) and Game.state.incubator_level == 1
			and Game.admin_change_level("incubator", -1) and Game.state.incubator_level == 0,
			"admin: inkubator w gore i w dol")
	# 13.1.1: lis w krzakach - 20 trafien bez psa, jedno z owczarkiem.
	var lis := Game.state
	lis.fox_lurk_left = 20.0
	var odszedl := false
	for i in 20:
		odszedl = Game.poke_lurking_fox()
	_check(odszedl and lis.fox_lurk_left <= 0.0, "lis w krzakach ucieka po 20 trafieniach")
	lis.fox_lurk_left = 20.0
	lis.set_building_level("dog", 2)
	_check(Game.poke_lurking_fox() and lis.fox_lurk_left <= 0.0, "z owczarkiem wystarczy jedno klikniecie")
	Game.state = stary_stan
	Cloud.player_id = stary_kod


## 13.0: noc wedlug slonca nad Polska - w nocy kury nie jedza, ale znosza.
## Kazda kolejna lepsza rasa zarabia na jajach wiecej niz poprzednie poziomy.
func _test_night() -> void:
	Daylight.force = -1
	_check(not Daylight.is_night(Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 6, "day": 21, "hour": 10, "minute": 0, "second": 0}))
			and Daylight.is_night(Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 6, "day": 21, "hour": 22, "minute": 0, "second": 0})),
			"czerwiec: 12:00 dzien, 00:00 noc (czas polski)")
	Daylight.force = -1
	var grudzien_17: float = Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 12, "day": 21, "hour": 16, "minute": 0, "second": 0})
	var grudzien_12: float = Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 12, "day": 21, "hour": 11, "minute": 0, "second": 0})
	_check(Daylight.is_night(grudzien_17) and not Daylight.is_night(grudzien_12),
			"grudzien: 17:00 juz noc, 12:00 dzien")
	Daylight.force = 1
	var st := _laying_state(["leghorn", "leghorn"], 100.0)
	var eggs_before := st.egg_count()
	Simulation.advance(st, 600.0 * GameData.time_scale())
	_check(is_equal_approx(st.feed, 100.0), "w nocy kury nie jedza (pasza %.1f)" % st.feed)
	_check(st.egg_count() > eggs_before, "w nocy kury dalej znosza (jaja %d, na ziemi %d, kur %d)" % [st.egg_count(), st.eggs_on_ground.size(), st.hen_count()])
	var glodne := _fresh_state(["leghorn", "leghorn"], 0.0)
	Simulation.advance(glodne, 7200.0 * GameData.time_scale())
	_check(glodne.hen_count() == 2, "w nocy glod stoi")
	Daylight.force = 0
	var poprzedni := 0.0
	var dotad := 0.0
	var poziom := -1
	for b: Dictionary in GameData.breeds():
		var zarobek := float(b["egg_value"]) / float(b["egg_seconds"])
		if int(b["coop_level"]) != poziom:
			poprzedni = dotad
			poziom = int(b["coop_level"])
		_check(zarobek > poprzedni, "%s zarabia wiecej niz rasy z nizszych kurnikow (%.2f > %.2f)"
				% [b["id"], zarobek, poprzedni])
		dotad = maxf(dotad, zarobek)


func _with_dog() -> FarmState:
	var s := _fresh_state(["leghorn"], 10.0)
	s.set_building_level("dog", 1)
	return s


## 12.22: plik data/rozbudowy.json (do recznej edycji przez wlasciciela) jest
## poprawny i gra naprawde z niego czyta - nazwy, ceny, pojemnosci, pasza,
## plot i pies.
func _test_upgrades_file() -> void:
	var bal: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))
	var plik: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/rozbudowy.json"))
	_check(bal is Dictionary and plik is Dictionary, "balance.json i rozbudowy.json to poprawny JSON")
	if not (bal is Dictionary and plik is Dictionary):
		return
	var problemy := GameData.apply_upgrades(bal, plik)
	_check(problemy.is_empty(), "rozbudowy.json bez bledow: %s" % ", ".join(problemy))
	var ile := {"kurnik": 10, "magazyn": 10, "inkubator": 10, "plot": 4, "pies": 2}
	for lista: String in ile:
		_check((plik.get(lista, []) as Array).size() == int(ile[lista]),
				"rozbudowy.json: %s ma %d poziomow" % [lista, ile[lista]])
	_check(plik.has("_jak_edytowac"), "rozbudowy.json ma instrukcje edycji")
	var zakupy: Array = plik.get("pasza_do_kupienia", [])
	_check(zakupy.size() == 2 and int(zakupy[0]["kg"]) == 20 and int(zakupy[1]["kg"]) == 500
			and int(zakupy[0]["znizka_proc"]) == 0 and int(zakupy[1]["znizka_proc"]) == 20,
			"pasza: worek 20 kg bez znizki, big-bag 500 kg -20% (wlasciciel 25.11)")
	# Ten sam plik po popsuciu numeru poziomu i nazwy - bledy maja byc nazwane.
	var zepsuty: Dictionary = (plik as Dictionary).duplicate(true)
	(zepsuty["kurnik"][2] as Dictionary)["poziom"] = 7
	(zepsuty["plot"][0] as Dictionary)["nazwa"] = ""
	var bledy := GameData.apply_upgrades({}, zepsuty)
	_check(bledy.size() == 2, "zepsuty plik rozbudow zglasza 2 bledy (zglasza %d)" % bledy.size())

	# Gra czyta z pliku: wartosci w balance() zgadzaja sie z plikiem.
	var kurnik: Array = plik["kurnik"]
	var coop: Dictionary = GameData.balance()["buildings"]["coop"]
	_check(String(coop.get("name", "")) == String(kurnik[0]["nazwa"]), "kurnik startowy ma nazwe z pliku")
	_check(int(coop.get("capacity", 0)) == int(kurnik[0]["miejsc"]), "kurnik startowy ma miejsca z pliku")
	for i in range(1, kurnik.size()):
		var u: Dictionary = coop["upgrades"][i - 1]
		_check(String(u["name"]) == String(kurnik[i]["nazwa"]) and is_equal_approx(float(u["price"]),
				float(kurnik[i]["cena"])) and int(u["capacity"]) == int(kurnik[i]["miejsc"]),
				"kurnik poziom %d: nazwa, cena i miejsca z pliku" % i)
	var magazyn: Array = plik["magazyn"]
	var stan := FarmState.new()
	for i in magazyn.size():
		stan.storage_level = i
		_check(stan.egg_capacity() == int(magazyn[i]["jaj"]), "magazyn %d: %d jaj z pliku" % [i, magazyn[i]["jaj"]])
		var opcje: Array = plik["pasza_do_kupienia"]
		for o in opcje.size():
			var pasza := stan.feed_pack(o)
			var kg := float(opcje[o]["kg"])
			var za_kg := float(plik["pasza_zl_kg"]) * (1.0 - float(opcje[o]["znizka_proc"]) / 100.0)
			_check(is_equal_approx(float(pasza["per_kg"]), za_kg) and is_equal_approx(float(pasza["size"]), kg)
					and String(pasza["unit"]) == String(opcje[o]["nazwa"])
					and is_equal_approx(float(pasza["price"]), round(kg * za_kg * 100.0) / 100.0),
					"magazyn %d: %s za %.2f zl z pliku" % [i, NumberFormat.feed_unit(pasza), float(pasza["price"])])
	var inkubator: Array = plik["inkubator"]
	for i in inkubator.size():
		stan.incubator_level = i
		_check(stan.incubator_slots() == int(inkubator[i]["jaj"]) / 3,
				"inkubator %d: %d jaj = %d pisklat naraz" % [i, inkubator[i]["jaj"], int(inkubator[i]["jaj"]) / 3])
	var ploty: Array = plik["plot"]
	for i in ploty.size():
		stan.guard_level = i + 1
		_check(is_equal_approx(stan.fox_block_chance(), float(ploty[i]["lis_zawraca_proc"]) / 100.0),
				"plot %d: lis zawraca w %s%%" % [i + 1, ploty[i]["lis_zawraca_proc"]])
	var psy: Array = plik["pies"]
	for i in psy.size():
		stan.dog_level = i + 1
		_check(is_equal_approx(stan.dog_interval(), float(psy[i]["probuje_co_s"]))
				and is_equal_approx(stan.dog_chance(), float(psy[i]["przegania_proc"]) / 100.0)
				and is_equal_approx(stan.dog_kill_chance(), float(psy[i]["zagryza_proc"]) / 100.0),
				"pies %d (%s) dziala wedlug pliku" % [i + 1, psy[i]["nazwa"]])
	# Format wagi i polskie koncowki w opisach poziomow.
	_check(NumberFormat.weight(25) == "25 kg" and NumberFormat.weight(2000) == "2 t"
			and NumberFormat.weight(1500) == "1,5 t", "waga paszy: 25 kg, 2 t, 1,5 t")
	_check(NumberFormat.count(22, "miejsce", "miejsca", "miejsc") == "22 miejsca"
			and NumberFormat.count(55, "miejsce", "miejsca", "miejsc") == "55 miejsc"
			and NumberFormat.count(1, "pisklę", "pisklęta", "piskląt") == "1 pisklę"
			and NumberFormat.count(13, "pisklę", "pisklęta", "piskląt") == "13 piskląt",
			"polskie koncowki liczebnikow")


## Drabinki rozbudowy (od 12.22 z data/rozbudowy.json): kazdy poziom ma
## nazwe zwyklym tekstem, jest drozszy od poprzedniego i cos realnie dodaje.
## Kurnik dodatkowo nigdy nie jest tanszy za miejsce niz poprzedni poziom.
## Inkubatory i magazyny tego nie maja - w realu wiekszy sprzet jest tanszy
## na sztuke, a ceny maja byc z rynku (wlasciciel 25.11).
func _test_upgrade_ladders() -> void:
	var drabinki := {
		"coop": ["capacity", GameData.balance().get("buildings", {}).get("coop", {})],
		"storage": ["egg_capacity", GameData.balance().get("buildings", {}).get("storage", {})],
		"incubator": ["slots", GameData.balance().get("incubator", {})],
	}
	for id: String in drabinki.keys():
		var pole: String = drabinki[id][0]
		var dane: Dictionary = drabinki[id][1]
		var upgrades: Array = dane.get("upgrades", [])
		_check(upgrades.size() >= 7, "%s ma co najmniej siedem poziomow (ma %d)"
				% [id, upgrades.size()])
		var poprzednia_cena := 0.0
		var poprzednia_wartosc := float(dane.get(pole, 0))
		var poprzedni_koszt_jednostki := 0.0
		for i in upgrades.size():
			var poziom: Dictionary = upgrades[i]
			var nazwa := String(poziom.get("name", ""))
			_check(not nazwa.is_empty(), "%s poziom %d ma nazwe" % [id, i + 1])
			_check(not nazwa.contains("_T"), "%s: nazwa %s to zwykly tekst, nie klucz" % [id, nazwa])
			var cena := float(poziom.get("price", 0))
			var wartosc := float(poziom.get(pole, 0))
			_check(cena > poprzednia_cena, "%s poziom %d jest drozszy od poprzedniego" % [id, i + 1])
			_check(wartosc > poprzednia_wartosc, "%s poziom %d cos dodaje" % [id, i + 1])
			if id == "coop":
				var koszt_jednostki := cena / maxf(1.0, wartosc - poprzednia_wartosc)
				_check(koszt_jednostki > poprzedni_koszt_jednostki,
						"%s poziom %d nie jest tanszy za miejsce niz poprzedni" % [id, i + 1])
				poprzedni_koszt_jednostki = koszt_jednostki
			poprzednia_cena = cena
			poprzednia_wartosc = wartosc

	# Pasza (wlasciciel 25.11): worek 20 kg bez znizki, big-bag 500 kg o 20%
	# taniej; magazyn ceny paszy NIE zmienia. Zadnego "rabatu"/"hurtu" w tekstach.
	var stan := FarmState.new()
	var worek0 := stan.feed_pack(0)
	var big0 := stan.feed_pack(1)
	_check(is_equal_approx(float(worek0["size"]), 20.0) and is_equal_approx(float(worek0["price"]), 40.0),
			"worek 20 kg za 40 zl (2 zl/kg, bez znizki)")
	_check(is_equal_approx(float(big0["size"]), 500.0) and is_equal_approx(float(big0["price"]), 800.0),
			"big-bag 500 kg za 800 zl (20%% taniej)")
	var poziomy: Array = GameData.balance().get("buildings", {}).get("storage", {}).get("upgrades", [])
	for i in poziomy.size():
		stan.storage_level = i + 1
		_check(is_equal_approx(float(stan.feed_pack(0)["price"]), 40.0)
				and is_equal_approx(float(stan.feed_pack(1)["price"]), 800.0),
				"magazyn %d nie zmienia ceny paszy" % (i + 1))
	for key: String in ["PANEL_BUY_FEED", "HINT_BUILDING_UPGRADED_STORAGE",
			"UPG_STORAGE_EFFECT", "PANEL_UPGRADE_NEXT", "PANEL_UPGRADE_SLIDE"]:
		var tekst := tr(key).to_lower()
		_check(not tekst.contains("rabat") and not tekst.contains("hurt"),
				"%s bez slow rabat/hurt: %s" % [key, tr(key)])

	# Inkubator nie moze wyprzedzic kurnika: nie ma gdzie wstawic piskląt.
	var coop_max := 0
	for poziom: Dictionary in (GameData.balance().get("buildings", {}).get("coop", {}).get("upgrades", []) as Array):
		coop_max = maxi(coop_max, int(poziom.get("capacity", 0)))
	var incu_max := 0
	for poziom: Dictionary in (GameData.balance().get("incubator", {}).get("upgrades", []) as Array):
		incu_max = maxi(incu_max, int(poziom.get("slots", 0)))
	_check(incu_max < coop_max, "pelny inkubator (%d) miesci sie w pelnym kurniku (%d)"
			% [incu_max, coop_max])


## Jaja psuja sie po szesciu godzinach ZEGARKA. Wlasciciel zglosil, ze po
## nocy magazyn pekal w szwach i cala ekonomia stawala na glowie.
func _test_egg_spoilage() -> void:
	var hours := float(GameData.balance().get("economy", {}).get("egg_spoil_hours", 0.0))
	_check(hours > 0.0, "jaja maja termin przydatnosci (%.1f h realnych)" % hours)
	var spoil_game := hours * 3600.0 * GameData.time_scale()

	var state := FarmState.new()
	state.add_egg("leghorn", 10)
	_check(state.egg_count() == 10, "dziesiec jaj w magazynie")

	# Pol terminu: nic sie jeszcze nie psuje.
	var polowa := Simulation.advance(state, spoil_game * 0.5)
	_check(int(polowa.get("eggs_spoiled", 0)) == 0, "po trzech godzinach jaja sa dobre")
	_check(state.egg_count() == 10, "magazyn nietkniety")

	# Dokladamy swieza partie — ona ma przetrwac dluzej niz pierwsza.
	state.add_egg("leghorn", 4)
	var reszta := Simulation.advance(state, spoil_game * 0.6)
	_check(int(reszta.get("eggs_spoiled", 0)) == 10, "stara dziesiatka sie zepsula")
	_check(state.egg_count() == 4, "swieza czworka zostaje (jest %d)" % state.egg_count())

	# I ona tez w koncu schodzi.
	var koniec := Simulation.advance(state, spoil_game)
	_check(int(koniec.get("eggs_spoiled", 0)) == 4, "swieza partia tez ma swoj termin")
	_check(state.egg_count() == 0, "magazyn pusty")
	_check(state.egg_ages.is_empty(), "metryka wieku posprzatana")

	# Sprzedajemy NAJSTARSZE najpierw: po dolozeniu swiezych i sprzedaniu
	# czesci w magazynie maja zostac te mlodsze.
	var sklep := FarmState.new()
	sklep.add_egg("leghorn", 6)
	Simulation.advance(sklep, spoil_game * 0.8)
	sklep.add_egg("leghorn", 6)
	_check(sklep.take_eggs("leghorn", 6) == 6, "sprzedane szesc jaj")
	var dalej := Simulation.advance(sklep, spoil_game * 0.3)
	_check(int(dalej.get("eggs_spoiled", 0)) == 0,
			"zostaly te swieze, wiec nic sie nie psuje tuz po sprzedazy")
	_check(sklep.egg_count() == 6, "w magazynie zostalo szesc mlodszych jaj")


## Szczepionka kosztuje wedlug wielkosci stada: 5 zl od kury.
func _test_vaccine_price() -> void:
	Game.new_game()
	Game.state.chickens.clear()
	_check(is_zero_approx(Game.vaccine_price()), "bez kur nie ma za co placic")
	for i in 7:
		Game.state.chickens.append(Chicken.create("leghorn"))
	var za_sztuke := float(GameData.balance().get("disease", {}).get("vaccine_price_per_hen", 0.0))
	_check(za_sztuke > 0.0, "szczepionka kosztuje cos za sztuke")
	_check(is_equal_approx(Game.vaccine_price(), 7.0 * za_sztuke),
			"siedem kur to siedem stawek (jest %.0f)" % Game.vaccine_price())
	Game.state.chickens[0].vaccinated = true
	_check(is_equal_approx(Game.vaccine_price(), 6.0 * za_sztuke),
			"za juz zaszczepiona kure nie placimy drugi raz")


## Po dluzszej przerwie ekran powitalny ma wymagac kodu zamiast "Graj dalej".
func _test_require_code_after_break() -> void:
	var session: Dictionary = GameData.balance().get("session", {})
	_check(bool(session.get("require_code", false)), "wymog kodu jest wlaczony")
	_check(is_zero_approx(float(session.get("require_code_after_minutes", -1.0))),
			"zero znaczy: pytaj ZAWSZE")

	Game.new_game()
	Game.is_new_player = true
	_check(not Game.must_enter_code(),
			"gracz bez farmy nie jest pytany — nie ma czego wczytywac")
	Game.is_new_player = false
	_check(Game.must_enter_code(), "gracz z farma jest pytany o kod przy kazdym wejsciu")

	# Zapis sprzed pieciu minut: gracz wchodzi bez kodu.
	var state := FarmState.new()
	state.intro_seen = true
	var zapis := SaveGame.to_dict(state)
	zapis["saved_at"] = Time.get_unix_time_from_system() - 5.0 * 60.0
	Game.apply_loaded_for_test(SaveGame.from_dict(zapis))
	_check(Game.must_enter_code(), "przy ustawieniu 'zawsze' kod jest potrzebny takze po pieciu minutach")

	# Zapis sprzed godziny: kod wymagany.
	zapis["saved_at"] = Time.get_unix_time_from_system() - 3600.0
	Game.apply_loaded_for_test(SaveGame.from_dict(zapis))
	_check(Game.must_enter_code(), "po godzinie przerwy trzeba wpisac kod")


## Nieudane wczytanie kodu NIE MOZE przestawic tozsamosci urzadzenia.
## Wlasciciel stracil tak dwie farmy: wpisal kod, pobranie sie nie udalo,
## urzadzenie zostalo z cudzym kodem i najblizszy autozapis wrzucil pod
## niego lokalna, pusta farme — kasujac prawdziwa.
func _test_failed_restore_keeps_identity() -> void:
	Game.new_game()
	var moj := Cloud.player_id
	_check(not moj.is_empty(), "urzadzenie ma swoj kod")

	_check(Game.restore_from_code("659722"), "proba wczytania rusza")
	_check(Cloud.player_id == moj,
			"w trakcie pobierania kod urzadzenia sie NIE zmienia (jest %s)" % Cloud.player_id)

	# Serwer odpowiada, ze takiej farmy nie ma.
	Game._on_cloud_pulled({}, true, "659722")
	_check(Cloud.player_id == moj,
			"po nieudanym wczytaniu kod zostaje nasz (jest %s)" % Cloud.player_id)

	# A gdy farma jednak przyjdzie, kod przechodzi na nia.
	var cudza := FarmState.new()
	cudza.money = 777.0
	cudza.chickens.append(Chicken.create("rhode"))
	var payload := SaveGame.to_dict(cudza)
	_check(Game.restore_from_code("659722"), "druga proba rusza")
	Game._on_cloud_pulled(payload, true, "659722")
	_check(Cloud.player_id == "659722",
			"po udanym wczytaniu urzadzenie przyjmuje kod farmy (jest %s)" % Cloud.player_id)
	_check(is_equal_approx(Game.state.money, 777.0), "stan przyszedl z serwera")
	_check(Game.state.chickens.size() == 1, "kury przyszly z serwera")
	Cloud.set_player_id(moj)


## Trzy bezpieczniki, ktore maja raz na zawsze zamknac droge do kasowania
## cudzych farm pustym zapisem.
func _test_push_guards() -> void:
	Game.new_game()
	var moj := Cloud.player_id
	_check(not Game.may_push_to_cloud(),
			"farma zalozona przed ekranem powitalnym czeka, nie leci na serwer")
	# Tak robi "Nowa farma" na ekranie powitalnym: dopiero to jest decyzja
	# gracza, zeby prowadzic wlasnie ta farme.
	Game.state.intro_seen = true
	_check(Game.may_push_to_cloud(),
			"wlasna, potwierdzona farma moze isc na serwer")

	# 1. Pusty stan nie idzie na serwer NIGDY.
	Game.state.chickens.clear()
	Game.state.corpses.clear()
	Game.state.incubating.clear()
	Game.state.chicks.clear()
	Game.state.eggs.clear()
	Game.state.egg_ages.clear()
	_check(Game.is_farm_empty(), "stan jest pusty")
	_check(not Game.may_push_to_cloud(),
			"pusta farma nie nadpisze niczego na serwerze")

	# 2. Kod, ktorego ta sesja nie zdobyla, jest zamkniety do zapisu.
	Game.new_game()
	# `new_game()` daje farme jeszcze NIEPOTWIERDZONA przez gracza, a takiej
	# nie wysylamy (osobny bezpiecznik, sprawdzany w tescie przerwy).
	# Tutaj udajemy farme, ktora gracz juz prowadzi.
	Game.state.intro_seen = true
	Game.state.chickens.append(Chicken.create("leghorn"))
	_check(Game.may_push_to_cloud(), "pelna wlasna farma znow moze isc")
	Cloud.set_player_id("999999")
	_check(not Game.may_push_to_cloud(),
			"pod cudzy kod nie piszemy, dopoki serwer nie odda nam tej farmy")

	# 3. W trakcie pobierania nic nie wysylamy.
	Cloud.set_player_id(moj)
	_check(Game.may_push_to_cloud(), "po powrocie na swoj kod zapis znow wolno")
	_check(Game.restore_from_code("888888"), "ruszamy po cudza farme")
	_check(not Game.may_push_to_cloud(), "w trakcie pobierania nic nie wysylamy")
	Game._on_cloud_pulled({}, true, "888888")
	_check(Cloud.player_id == moj, "nieudane pobranie nie zmienia kodu")
	_check(Game.may_push_to_cloud(), "i nie odbiera prawa do wlasnego zapisu")

	# Po UDANYM pobraniu cudzej farmy wolno pod nia pisac.
	var cudza := FarmState.new()
	cudza.intro_seen = true
	cudza.chickens.append(Chicken.create("rhode"))
	_check(Game.restore_from_code("888888"), "druga proba")
	Game._on_cloud_pulled(SaveGame.to_dict(cudza), true, "888888")
	_check(Cloud.player_id == "888888", "kod przeszedl na nas")
	_check(Game.may_push_to_cloud(), "teraz wolno zapisywac te farme")
	Cloud.set_player_id(moj)


## Limit jaj w magazynie. Istnieje po to, zeby gra nie przechodzila sie sama:
## bez niego mozna bylo wrocic po dobie i zastac gore jaj.
func _test_egg_capacity() -> void:
	var storage: Dictionary = GameData.balance().get("buildings", {}).get("storage", {})
	var state := FarmState.new()
	var cap := int(storage.get("egg_capacity", 0))
	_check(cap > 50, "mala szopa ma sensowny limit (%d)" % cap)
	_check(state.egg_capacity() == cap, "limit z balance.json (jest %d)" % state.egg_capacity())

	_check(state.add_egg("leghorn", cap - 50) == cap - 50, "jaja do limitu bez 50 sie mieszcza")
	_check(state.egg_room() == 50, "zostalo miejsca na 50")
	_check(state.add_egg("leghorn", 90) == 50, "z 90 jaj miesci sie tylko 50")
	_check(state.egg_count() == cap, "magazyn pelny, ani jednego wiecej")
	_check(state.add_egg("rhode", 10) == 0, "do pelnego nic juz nie wejdzie")

	# Kazdy poziom magazynu podnosi limit.
	var poprzedni := 200
	var ups: Array = storage.get("upgrades", [])
	for i in ups.size():
		var lim := int(ups[i].get("egg_capacity", 0))
		_check(lim > poprzedni, "magazyn %d miesci wiecej jaj niz poprzedni (%d > %d)"
				% [i + 1, lim, poprzedni])
		poprzedni = lim
	# 13.2 (wlasciciel 27.11): pojemnosc rosnie skokami - 200, 1000, 3000,
	# 10 000 ... 2 000 000 (ok. godzina znoszenia stada z danego etapu).
	var skoki := [200, 1000, 3000, 10000, 25000, 60000, 150000, 350000, 800000, 2000000]
	var jest: Array = [int(storage.get("egg_capacity", 0))]
	for u: Dictionary in ups:
		jest.append(int(u.get("egg_capacity", 0)))
	_check(jest == skoki, "magazyny: %s" % str(jest))

	# Kura przy pelnym magazynie nie dokłada do niego jaj — i o to chodzi.
	var farm := _fresh_state(["leghorn", "leghorn"], 1000.0)
	farm.chickens.append(Chicken.create_rooster("leghorn"))
	for chicken: Chicken in farm.chickens:
		chicken.vaccinated = true
	farm.add_egg("leghorn", farm.egg_capacity())
	_check(farm.egg_room() == 0, "magazyn zapchany przed testem")
	var wynik := Simulation.advance(farm, 3600.0)
	_check(farm.egg_count() == farm.egg_capacity(), "magazyn nie przekracza limitu")
	_check(int(wynik.get("eggs_lost", 0)) > 0,
			"gra liczy jaja, ktore przepadly z braku miejsca (%d)" % int(wynik.get("eggs_lost", 0)))


## Pies w akcji: probuje do skutku, a owczarek czasem zagryza lisa.
## Pies ma pilnowac TAKZE wtedy, gdy gracza nie ma przy grze. Do 12.15
## przy grze w tle lis zabieral caly lup naraz, a pies nie dostawal nawet
## jednego rzutu kostka — czyli w nocy, gdy jest najbardziej potrzebny,
## nie robil nic. Sredni lup z wielu wizyt: bez psa, z kundlem, z owczarkiem.
## Sklep sprzedaje jaja partiami po economy.egg_sale_lot, najstarsze najpierw
## - bez wzgledu na rase, bo to najstarsze gnija najszybciej.
func _test_egg_lots() -> void:
	Game.new_game()
	var s := Game.state
	s.eggs.clear()
	s.egg_ages.clear()
	s.add_egg("cemani", 30)
	s.age_eggs(3600.0, 999999.0)  # cemani: godzina
	s.add_egg("leghorn", 150)
	s.age_eggs(600.0, 999999.0)   # cemani 70 min, leghorn 10 min
	s.add_egg("marans", 20)     # swieze
	var partia := s.oldest_eggs(100)
	_check(int(partia.get("cemani", 0)) == 30, "partia zaczyna od najstarszych (cemani 30)")
	_check(int(partia.get("leghorn", 0)) == 70, "potem kolejne wedlug wieku (leghorn 70)")
	_check(not partia.has("marans"), "swieze jaja zostaja")
	_check(s.egg_count() == 200, "podglad partii niczego nie zabiera")
	var oczekiwane := FarmState.eggs_worth(partia)
	var pieniadze := s.money
	var zarobek := Game.sell_eggs(100)
	_check(is_equal_approx(zarobek, oczekiwane), "sprzedaz daje tyle, ile pokazal przycisk")
	_check(is_equal_approx(s.money, pieniadze + zarobek), "pieniadze doszly")
	_check(s.egg_count() == 100, "zostalo 100 jaj")
	_check(int(s.eggs.get("cemani", 0)) == 0 and int(s.eggs.get("leghorn", 0)) == 80
			and int(s.eggs.get("marans", 0)) == 20, "zeszly dokladnie te z partii")
	Game.sell_eggs(100)
	Game.sell_eggs(100)
	_check(s.egg_count() == 0, "resztka ponizej partii tez sie sprzedaje")
	_check(Game.egg_sale_lot() == int(GameData.balance()["economy"].get("egg_sale_lot", -1)),
			"wielkosc partii z balance.json")

	for para: Array in [[1, "1 jajo"], [2, "2 jaja"], [4, "4 jaja"], [5, "5 jaj"], [12, "12 jaj"],
			[14, "14 jaj"], [22, "22 jaja"], [100, "100 jaj"], [1003, NumberFormat.grouped(1003) + " jaja"]]:
		_check(NumberFormat.eggs(int(para[0])) == String(para[1]),
				"odmiana: %s (jest '%s')" % [para[1], NumberFormat.eggs(int(para[0]))])
	# Cena za kilogram ponizej zlotowki nie moze wyjsc jako "0 zl".
	_check(NumberFormat.small_money(0.9) == "90 gr", "90 groszy to '90 gr'")


func _test_dog_offline() -> void:
	var proby := 300
	var sredni := func(dog: int) -> Array:
		var zabite := 0
		var zagryzione := 0
		for i in proby:
			var hens: Array[String] = []
			for j in 30:
				hens.append("leghorn")
			var state := _fresh_state(hens, 100000.0)
			state.dog_level = dog
			var out := {"fox_took": 0, "died_hunger": 0, "died_disease": 0, "fox_arrived": 0}
			Simulation._fox_arrives(state, out, 1 << 30, true)
			zabite += int(out["fox_took"])
			zagryzione += int(out.get("fox_killed", 0))
			if i == 0:
				_check(state.fox_visit_left <= 0.0 and state.fox_kill_left == 0,
						"po wizycie w tle stan lisa jest wyczyszczony (pies %d)" % dog)
		return [float(zabite) / proby, zagryzione]
	var bez: Array = sredni.call(0)
	var kundel: Array = sredni.call(1)
	var owczarek: Array = sredni.call(2)
	var fox_cfg: Dictionary = GameData.balance()["fox"]
	var oczekiwany := (float(fox_cfg.get("kills_min", 3)) + float(fox_cfg.get("kills_max", 10))) / 2.0
	_check(bez[0] > oczekiwany * 0.85,
			"bez psa lis w tle bierze pelny lup (srednio %.1f, oczekiwane %.1f)" % [bez[0], oczekiwany])
	_check(kundel[0] < bez[0] * 0.85,
			"kundel ratuje kury takze w tle (%.1f vs %.1f)" % [kundel[0], bez[0]])
	_check(owczarek[0] < kundel[0],
			"owczarek ratuje wiecej niz kundel (%.1f vs %.1f)" % [owczarek[0], kundel[0]])
	_check(owczarek[0] >= 1.0, "pierwsza kura i tak ginie przy wejsciu lisa")
	_check(int(owczarek[1]) > 0, "owczarek zagryza lisa takze w tle (%d razy)" % int(owczarek[1]))
	_check(int(kundel[1]) == 0, "kundel nigdy nie zabija lisa")


func _test_dog_in_action() -> void:
	var hens: Array[String] = []
	for i in 40:
		hens.append("leghorn")

	# Bez psa lis wybiera cala swoja pule.
	var bez_psa := 0
	for i in 25:
		var a := _fresh_state(hens, 0.0)
		_arm_fox(a)
		bez_psa += _przezyj_wizyte(a)

	# Z kundlem gina tylko te kury, ktore lis zdazy porwac, zanim pies
	# trafi swoja kostka.
	var z_kundlem := 0
	var przegonien := 0
	for i in 25:
		var b := _fresh_state(hens, 0.0)
		b.dog_level = 1
		_arm_fox(b)
		var przed := b.hen_count()
		_przezyj_wizyte(b)
		z_kundlem += przed - b.hen_count()
	_check(z_kundlem < bez_psa, "z kundlem gina mniej kur (%d wobec %d)" % [z_kundlem, bez_psa])

	# Owczarek dziala czesciej i mocniej.
	var z_owczarkiem := 0
	var zagryzien := 0
	for i in 25:
		var c := _fresh_state(hens, 0.0)
		c.dog_level = 2
		_arm_fox(c)
		var przed := c.hen_count()
		var wynik := Simulation.advance(c, 1.0)
		zagryzien += int(wynik.get("fox_killed", 0))
		var licznik := 0
		while c.fox_visit_left > 0.0 and licznik < 2000:
			var krok := Simulation.advance(c, 1.0)
			zagryzien += int(krok.get("fox_killed", 0))
			licznik += 1
		z_owczarkiem += przed - c.hen_count()
	_check(z_owczarkiem < z_kundlem,
			"z owczarkiem gina jeszcze mniejsze straty (%d wobec %d)" % [z_owczarkiem, z_kundlem])
	_check(zagryzien > 0, "owczarek czasem zagryza lisa (%d na 25 wizyt)" % zagryzien)

	# Zagryziony lis odracza nastepnego piec razy.
	var d := _fresh_state(hens, 0.0)
	d.dog_level = 2
	_arm_fox(d)
	Simulation.advance(d, 1.0)
	var bezpiecznik := 0
	while d.fox_visit_left > 0.0 and bezpiecznik < 2000:
		Simulation.advance(d, 1.0)
		bezpiecznik += 1
	if d.fox_next_multiplier > 1.0:
		_check(is_equal_approx(d.fox_next_multiplier,
				float(GameData.balance()["fox"].get("killed_return_multiplier", 0.0))),
				"po zagryzieniu odstep rosnie o killed_return_multiplier")
	_disarm_fox()


## Kurnik na maksa. Testy zakupow i cen nie sa o tym, ktora rasa jest
## zamknieta za poziomem kurnika — bez tego kupno cemani w nowej grze
## odpadaloby na bramce i testy mowilyby o czym innym, niz deklaruja.
## Samo bramkowanie ma wlasny test: `_test_breed_gating`.
func _open_all_breeds() -> void:
	Game.state.coop_level = (GameData.balance().get("buildings", {}).get(
			"coop", {}).get("upgrades", []) as Array).size()


## Drozsza rasa wymaga wiekszego kurnika.
func _test_breed_gating() -> void:
	Game.new_game()
	Game.state.money = 1000000.0
	Game.state.coop_level = 0
	_check(Game.breed_allowed("leghorn"), "leghorna kupisz od pierwszego dnia")
	_check(not Game.breed_allowed("cemani"), "cemani nie wstawisz do szopy na 20 sztuk")
	_check(not Game.buy_hen("cemani"), "zakup cemani odpada na bramce")
	_check(Game.buy_hen("leghorn"), "leghorn wchodzi bez przeszkod")

	# Progi rosna razem z cena rasy.
	var poprzedni := 0
	var rasy: Array = GameData.breeds()
	var posortowane: Array = rasy.duplicate()
	posortowane.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("price", 0)) < float(b.get("price", 0)))
	for rasa: Dictionary in posortowane:
		var prog := int(rasa.get("coop_level", 0))
		_check(prog >= poprzedni, "%s nie wymaga mniej niz tansza rasa (%d >= %d)"
				% [rasa.get("id"), prog, poprzedni])
		poprzedni = prog
	_check(poprzedni > 0, "najdrozsza rasa naprawde czegos wymaga (poziom %d)" % poprzedni)

	# Po rozbudowie kurnika rasa sie otwiera.
	_open_all_breeds()
	_check(Game.breed_allowed("cemani"), "pelny kurnik otwiera wszystkie rasy")
	_check(Game.buy_hen("cemani"), "i cemani da sie kupic")

func _test_event_rules() -> void:
	var fox: Dictionary = GameData.balance().get("fox", {})
	var disease: Dictionary = GameData.balance().get("disease", {})
	_check(int(fox.get("grace_minutes", 0)) == 30, "lis: pol godziny spokoju na start")
	_check(int(disease.get("grace_minutes", 0)) == 30, "choroba: pol godziny spokoju na start")
	_check(int(fox.get("min_hens", 0)) == 5, "lis: nie rusza stada mniejszego niz piec")
	# Choroba od 12.20: zero szansy do 10 ptakow wynika z krzywej.
	_check(FarmState.disease_rate_per_hour(10) == 0.0, "choroba: stado do 10 ptakow bez szans")

	# Licznik czasu gry idzie od zalozenia farmy i to on otwiera furtke.
	var state := _fresh_state(["leghorn"], 100000.0)
	_check(is_zero_approx(state.played_seconds()), "nowa farma ma zerowy licznik czasu")
	Simulation.advance(state, 1800.0)
	_check(absf(state.played_seconds() - 1800.0) < 1.0,
			"po pol godziny licznik pokazuje pol godziny (%.0f s)" % state.played_seconds())

	# Lis: jedna kostka co roll_minutes, w grze i w tle (12.21).
	_check(float(fox.get("roll_minutes", 0.0)) > 0.0, "lis: odstep kostki > 0")
	_check(not fox.has("offline_roll_hours") and not fox.has("offline_chance"),
			"lis: nie ma osobnej kostki dla gry w tle")
	for klucz: String in ["chance", "massacre_chance"]:
		var p := float(fox.get(klucz, -1.0))
		_check(p >= 0.0 and p <= 1.0, "lis: %s miedzy 0 a 1 (%.3f)" % [klucz, p])
	_check(int(fox.get("kills_min", 0)) >= 1
			and int(fox.get("kills_max", 0)) >= int(fox.get("kills_min", 0)),
			"lis: lup min >= 1 i max >= min")
	_check(float(fox.get("kill_interval_min", 0.0)) > 0.0
			and float(fox.get("kill_interval_max", 0.0)) >= float(fox.get("kill_interval_min", 0.0)),
			"lis: odstep miedzy zabojstwami dodatni, max >= min")
	_check(float(fox.get("killed_return_multiplier", 0.0)) >= 1.0,
			"zagryziony lis nie wraca szybciej niz zwykly")

	# Choroba: liczby od wlasciciela (25.11).
	_check(is_equal_approx(float(disease.get("spread_seconds", 0.0)), 60.0), "choroba: zaraza co minute")
	_check(is_equal_approx(float(disease.get("survive_share_min", -1.0)), 0.0)
			and is_equal_approx(float(disease.get("survive_share_max", 0.0)), 0.3)
			and is_equal_approx(float(disease.get("survive_share_step", 0.0)), 0.1),
			"choroba: przezywa 0-30% chorych, co 10%")
	_check(is_equal_approx(float(disease.get("calm_hours_min", 0.0)), 3.0)
			and is_equal_approx(float(disease.get("calm_hours_max", 0.0)), 12.0),
			"choroba: 3-12 godzin spokoju")

	# Pomiar na zywo: stado 50 bez szczepien w ciagu doby choruje,
	# a stado 12 rzadko. Bez lisa: jego rzez potrafi wybic stado, zanim
	# choroba zdazy wybuchnac.
	var fox_snapshot := _snapshot_event("fox")
	_never_event("fox")
	var duze := 0
	var male := 0
	for i in 10:
		var stado50 := _herd(50)
		_past_grace(stado50)
		var stado12 := _herd(12)
		_past_grace(stado12)
		for h in 24:
			duze += 1 if int(Simulation.advance(stado50, 3600.0 * GameData.time_scale()).get("outbreak", 0)) > 0 else 0
			male += 1 if int(Simulation.advance(stado12, 3600.0 * GameData.time_scale()).get("outbreak", 0)) > 0 else 0
	_check(duze >= 10, "stado 50: kilka ognisk na dobe (%d w 10 dob)" % duze)
	_check(male < duze, "stado 12 choruje rzadziej niz 50 (%d wobec %d)" % [male, duze])
	_restore_event("fox", fox_snapshot)


func _test_server_diagnosis() -> void:
	var cases := [
		[HTTPRequest.RESULT_SUCCESS, 401, -1, "RLS"],
		[HTTPRequest.RESULT_SUCCESS, 403, -1, "RLS"],
		[HTTPRequest.RESULT_SUCCESS, 404, -1, "saves"],
		[HTTPRequest.RESULT_SUCCESS, 409, -1, "UNIQUE"],
		[HTTPRequest.RESULT_SUCCESS, 500, -1, "500"],
		[HTTPRequest.RESULT_TIMEOUT, 0, -1, "czas oczekiwania"],
		[HTTPRequest.RESULT_SUCCESS, 200, 0, "żadnego wiersza"],
		[HTTPRequest.RESULT_SUCCESS, 200, 1, "1"],
	]
	for case: Array in cases:
		Cloud.last_action = "odczyt"
		Cloud.last_result = int(case[0])
		Cloud.last_http_code = int(case[1])
		Cloud.last_rows = int(case[2])
		var said := Cloud.describe_last()
		_check(said.contains(String(case[3])),
				"kod %d daje podpowiedz o '%s' (jest: %s)" % [int(case[1]), case[3], said])

	Cloud.last_action = "zapis"
	Cloud.last_result = HTTPRequest.RESULT_SUCCESS
	Cloud.last_http_code = 201
	_check(Cloud.describe_last().contains("przeszedł"), "udany zapis melduje sie wprost")

	Cloud.last_action = ""
	_check(not Cloud.describe_last().is_empty(), "przed pierwsza rozmowa tez cos mowimy")


## Pelny kurnik: inkubator ma odmowic, a nie przyjac jaja i zatrzymac pisklę
## w kolejce bez slowa wyjasnienia.
func _test_coop_limit() -> void:
	Game.new_game()
	Game.state.money = 1000000.0
	var capacity := Game.state.coop_capacity()
	while Game.state.coop_occupied() < capacity:
		Game.state.chickens.append(Chicken.create("leghorn"))
	Game.state.eggs["leghorn"] = 100
	_check(Game.state.coop_free() == 0, "kurnik zapelniony do ostatniego miejsca")
	_check(not Game.can_incubate("leghorn"), "pelny kurnik blokuje wkladanie jaj")
	_check(Game.incubation_blocked_by_coop("leghorn"), "powodem jest wlasnie brak miejsca")
	_check(not Game.incubate("leghorn"), "proba wylegu konczy sie odmowa")
	_check(int(Game.state.eggs.get("leghorn", 0)) == 100, "odmowa nie zjada jaj")

	# Jedno wolne miejsce wystarczy na jedna partie, ale nie na dwie.
	Game.state.chickens.remove_at(0)
	_check(Game.state.coop_free() == 1, "zwolnilo sie jedno miejsce")
	_check(Game.incubate("leghorn"), "na wolne miejsce wyleg rusza")
	_check(Game.state.coop_free() == 0, "partia w inkubatorze rezerwuje to miejsce")
	_check(not Game.can_incubate("leghorn"), "druga partia nie ma juz gdzie wyjsc")

	# Pisklę i tak nie przepada: czeka, az miejsce sie znajdzie.
	var waiting := _fresh_state(["leghorn"], 1000.0)
	waiting.coop_level = 0
	while waiting.coop_occupied() < waiting.coop_capacity():
		waiting.chickens.append(Chicken.create("leghorn"))
	var chick := Chick.create("leghorn")
	chick.grown = chick.total_seconds()
	waiting.chicks.append(chick)
	Simulation.advance(waiting, 60.0)
	_check(waiting.chicks.size() == 1, "pisklę czeka na miejsce, nie znika")
	waiting.chickens.remove_at(0)
	Simulation.advance(waiting, 2.0)
	_check(waiting.chicks.is_empty(), "po zwolnieniu miejsca pisklę wchodzi do kurnika")
	Game.new_game()


## Kogut: warunek znoszenia, osobny towar w sklepie i migracja starych zapisow.
func _test_roosters() -> void:
	var seconds := float(GameData.breed("leghorn").get("egg_seconds", 0.0))

	# Same kury, bez koguta: przez dziesiec pelnych cykli ani jednego jajka.
	var lonely := _fresh_state(["leghorn", "leghorn"], 10000.0)
	for hen: Chicken in lonely.chickens:
		hen.vaccinated = true
	_check(int(Simulation.advance(lonely, seconds * 10.0)["eggs_laid"]) == 0,
			"bez koguta stado nie znosi nic")
	var missing := lonely.breeds_without_rooster()
	_check(missing.size() == 1 and missing[0] == "leghorn", "stan wskazuje rase bez koguta")

	# Dokladamy koguta i te same kury zaczynaja niesc.
	lonely.chickens.append(Chicken.create_rooster("leghorn"))
	_check(lonely.has_rooster("leghorn"), "kogut jest w stadzie")
	_check(int(Simulation.advance(lonely, seconds)["eggs_laid"]) > 0,
			"z kogutem te same kury juz nioska")
	_check(lonely.breeds_without_rooster().is_empty(), "nie brakuje juz zadnego koguta")

	# Kogut nie znosi, nawet gdy zostanie sam.
	var only_cocks := FarmState.new()
	only_cocks.feed = 1000.0
	only_cocks.chickens.append(Chicken.create_rooster("leghorn"))
	only_cocks.chickens[0].vaccinated = true
	_check(int(Simulation.advance(only_cocks, seconds * 5.0)["eggs_laid"]) == 0,
			"sam kogut nie zniesie jajka")

	# Kogut jednej rasy nie obsluguje kur innej rasy.
	var mixed := _fresh_state(["rhode"], 10000.0)
	mixed.chickens[0].vaccinated = true
	mixed.chickens.append(Chicken.create_rooster("leghorn"))
	var rhode_seconds := float(GameData.breed("rhode").get("egg_seconds", 0.0))
	_check(int(Simulation.advance(mixed, rhode_seconds * 4.0)["eggs_laid"]) == 0,
			"kogut leghorna nie pomaga kurom rhode")

	# Liczenie: kogut jest ptakiem w kurniku, ale nie kura w statystyce.
	var counted := _laying_state(["leghorn", "leghorn"])
	_check(counted.hen_count() == 3, "kurnik liczy koguta razem z kurami")
	_check(counted.laying_hen_count() == 2 and counted.rooster_count() == 1,
			"kury i koguty licza sie osobno")
	_check(counted.hens_of_breed("leghorn", false, true) == 1, "kogut danej rasy policzony")
	_check(int(counted.hens_by_breed().get("leghorn", 0)) == 2,
			"spis stada wedlug ras pomija koguty")

	# Sklep: kupno i sprzedaz koguta, cena taka sama jak za kure.
	Game.new_game()
	Game.state.money = 100000.0
	var cocks_before := Game.state.rooster_count()
	_check(Game.buy_hen("rhode", true), "kogut do kupienia w sklepie")
	_check(Game.state.rooster_count() == cocks_before + 1, "kupiony kogut trafil do stada")
	_check(Game.state.has_rooster("rhode"), "to kogut wlasciwej rasy")
	_check(Game.sell_hen("rhode", true) > 0.0, "koguta da sie sprzedac")
	_check(not Game.state.has_rooster("rhode"), "sprzedany kogut zniknal ze stada")
	Game.new_game()

	# Migracja: zapis sprzed wersji 5 nie znal kogutow, wiec wczytana farma
	# dostaje po jednym na kazda posiadana rase — inaczej stanelaby w miejscu.
	var old_save := {
		"version": 4,
		"money": 10.0,
		"feed": 5.0,
		"chickens": [
			{"breed": "leghorn", "vax": true},
			{"breed": "leghorn", "vax": true},
			{"breed": "cemani", "vax": false},
		],
	}
	var loaded: Dictionary = SaveGame.from_dict(old_save)
	var migrated: FarmState = loaded.get("state")
	_check(migrated != null and migrated.has_rooster("leghorn") and migrated.has_rooster("cemani"),
			"stary zapis dostaje koguta kazdej posiadanej rasy")
	_check(migrated != null and migrated.laying_hen_count() == 3,
			"migracja nie zmienia liczby kur")
	_check(migrated != null and migrated.rooster_count() == 2,
			"migracja dodaje dokladnie jednego koguta na rase")


## Przy pelnym wybiegu wolne miejsca musza krazyc po stadzie. Wczesniej brala
## je zawsze kura z poczatku tablicy i rasy kupione pozniej nie znosily nic:
## pomiar dal 292 jaja leghorna i 0 cemani.
func _test_lay_fairness() -> void:
	var hens: Array[String] = []
	for i in 20:
		hens.append("leghorn")
	hens.append("cemani")
	var state := _laying_state(hens, 100000.0)
	for bird: Chicken in state.chickens:
		bird.vaccinated = true
	# Wybieg zostaje pelny: zbieramy po jednym jajku na szesc sekund.
	for i in 1800:
		Simulation.advance(state, 1.0)
		if i % 6 == 0 and not state.eggs_on_ground.is_empty():
			var breed_id: String = state.eggs_on_ground[0]
			state.eggs_on_ground.remove_at(0)
			state.add_egg(breed_id)
	var cemani := int(state.eggs.get("cemani", 0)) + state.eggs_on_ground.count("cemani")
	_check(cemani > 0, "przy pelnym wybiegu cemani tez znosi (zniosla %d)" % cemani)


func _test_offline_eggs() -> void:
	var capacity := int(GameData.balance().get("run", {}).get("max_eggs_on_ground", 30))
	var hens: Array[String] = []
	for i in 10:
		hens.append("leghorn")

	# Na zywo: na wybiegu lezy najwyzej `capacity` jaj, reszta idzie od razu
	# do magazynu. Zadne jajko nie przepada i zadna kura nie czeka.
	# Lisa i choroby wylaczamy: test mierzy ksiegowanie jaj, a nie to, ile kur
	# zjadl lis. Przy lupie 30-90% stada roznica miedzy przebiegami siegala
	# 30% i test potrafil zaswiecic sie na czerwono bez zadnego bledu w kodzie.
	_never_event("fox")
	_never_event("disease")
	var live := _laying_state(hens, 100000.0)
	for bird: Chicken in live.chickens:
		bird.vaccinated = true
	var live_result := Simulation.advance(live, 3.0 * 3600.0)
	_check(live.eggs_on_ground.size() <= capacity, "na zywo wybieg nie przekracza limitu")
	_check(live.egg_count() > 0, "na zywo nadmiar trafia do magazynu")
	# Ksiegowanie musi sie zgadzac z uwzglednieniem jaj, ktore przelezaly
	# swoje szesc godzin i sie zepsuly.
	_check(live.egg_count() + live.eggs_on_ground.size() + int(live_result.get("eggs_spoiled", 0))
			== int(live_result["eggs_laid"]),
			"na zywo nic nie ginie bez sladu: wybieg + magazyn + zepsute = cala produkcja")

	# Offline: te same kury przez ten sam czas odkladaja tyle samo, tylko
	# wszystko od razu w magazynie.
	var away := _laying_state(hens, 100000.0)
	for bird: Chicken in away.chickens:
		bird.vaccinated = true
	var away_result := Simulation.advance(away, 3.0 * 3600.0, true)
	_check(away.eggs_on_ground.is_empty(), "offline nic nie laduje na wybiegu")
	_check(away.egg_count() > capacity, "offline magazyn zbiera wiecej, niz miesci wybieg")
	_check(int(away_result["eggs_laid"]) == away.egg_count() + int(away_result.get("eggs_spoiled", 0)),
			"licznik zgadza sie z magazynem po odjeciu zepsutych")
	# Offline wychodzi nawet odrobine lepiej, bo `offline_max_share` ogranicza
	# straty od lisa do polowy stada. Chodzi o to, zeby nieobecnosc niczego
	# nie marnowala — nie o to, zeby wyszlo co do jajka tyle samo.
	_check(float(away_result["eggs_laid"]) >= float(live_result["eggs_laid"]) * 0.99,
			"nieobecnosc nie marnuje nocnej produkcji (%d wobec %d)" % [
				int(away_result["eggs_laid"]), int(live_result["eggs_laid"])])
	_check(int(away.eggs.get("leghorn", 0)) == away.egg_count(), "jaja zapisane pod wlasciwa rasa")
	GameData.reload()
	Game.new_game()


## Rozliczanie czasu miedzy klatkami. Zminimalizowana przegladarka na telefonie
## zamraza strone calkiem, wiec po powrocie przychodzi jedna klatka z wielka
## dziura — i ta dziura musi sie policzyc jak czas offline, a nie wyladowac
## w koszu.
func _test_time_gap() -> void:
	var capacity := int(GameData.balance().get("run", {}).get("max_eggs_on_ground", 30))

	# Zwykla klatka: jaja ladu ja na wybiegu, bo gracz patrzy.
	Game.new_game()
	Game.state.feed = 100000.0
	var egg_seconds := float(GameData.breed("leghorn").get("egg_seconds", 4.0))
	for i in 10:
		# Kury tuz przed zniesieniem, zeby jedna krotka klatka wystarczyla.
		Game.state.chickens.append(Chicken.create("leghorn", egg_seconds - 1.0))
	_check(not Game.apply_gap(5.0, true), "krotka przerwa idzie zwykla sciezka")
	_check(Game.state.eggs_on_ground.size() > 0, "przy graczu jaja ladu ja na wybiegu")
	_check(Game.state.eggs_on_ground.size() <= capacity,
			"przy graczu wybieg nie przekracza limitu")

	# Dziura dluzsza niz krok na zywo: liczymy ja jak czas offline.
	Game.new_game()
	Game.state.feed = 100000.0
	for i in 10:
		Game.state.chickens.append(Chicken.create("leghorn"))
	_check(Game.apply_gap(3.0 * 3600.0, true), "dluga dziura idzie sciezka offline")
	_check(Game.state.egg_count() > capacity, "po dlugiej dziurze magazyn ma wiecej, niz miesci wybieg")
	_check(Game.state.eggs_on_ground.is_empty(), "po dlugiej dziurze nic nie lezy na wybiegu")

	# Okno nieaktywne: czas zbiera sie i rozlicza dopiero po powrocie.
	Game.new_game()
	Game.state.feed = 100000.0
	for i in 10:
		Game.state.chickens.append(Chicken.create("leghorn"))
	var feed_before := Game.state.feed
	_check(not Game.apply_gap(3.0 * 3600.0, false), "przy nieaktywnym oknie nic sie nie rozlicza od razu")
	_check(is_equal_approx(Game.state.feed, feed_before), "czas czeka, pasza stoi")
	_check(Game.apply_gap(1.0, true), "po powrocie uzbierany czas rozlicza sie naraz")
	_check(Game.state.feed < feed_before, "pasza zeszla za caly czas nieobecnosci")
	_check(Game.state.egg_count() > 0, "jaja z nieobecnosci czekaja w magazynie")

	# NOC W TLE. Wpadka z 24 listopada: karta stala otwarta przez noc, okno
	# nieaktywne. Gospodarstwo nic nie liczylo, ale autozapis co osiem sekund
	# wbijal swiezy stempel czasu. Po wyczyszczeniu ciasteczek i wczytaniu
	# farmy gra widziala "od zapisu minela chwila" i cala noc przepadala.
	# Serwer potwierdzil: miedzy 19:56 a 7:04 nie przyszedl zaden zapis.
	# Zapis musi niesc NIEROZLICZONY czas, a nie moment zapisania pliku.
	Game.new_game()
	Game.state.feed = 100000.0
	for i in 10:
		Game.state.chickens.append(Chicken.create("leghorn"))
	# Bez lisa: od 12.21 w tle przychodzi co godzine i potrafi wybic stado,
	# a ten test mierzy samo rozliczenie czasu.
	var lis_noc := _snapshot_event("fox")
	_never_event("fox")
	var noc := 8.0 * 3600.0
	Game.apply_gap(noc, false)
	var jaja_przed := Game.state.egg_count()
	var sciezka := "user://test_noc.json"
	_check(SaveGame.save_state(Game.state, sciezka, Game._away_seconds),
			"zapis w czasie nieaktywnego okna sie udaje")
	var nocny := SaveGame.load_state(sciezka)
	_check(not nocny.is_empty(), "nocny zapis sie wczytuje")
	# Tolerancja, bo miedzy zapisem a odczytem uplywa ulamek sekundy.
	_check(absf(float(nocny["elapsed"]) - noc) < 30.0,
			"zapis niesie cala noc do rozliczenia (%.0f s zamiast %.0f)"
					% [float(nocny["elapsed"]), noc])
	Game.apply_loaded_for_test(nocny)
	_check(Game.state.egg_count() > jaja_przed,
			"po wczytaniu noc zostaje rozliczona, a nie wyrzucona")
	_restore_event("fox", lis_noc)
	_check(is_zero_approx(Game._away_seconds), "dlug czasu zostal spłacony przy wczytaniu")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(sciezka))

	# A zwykly zapis, bez zaleglosci, ma miec stempel z teraz.
	Game.new_game()
	var zwykly := SaveGame.from_dict(SaveGame.to_dict(Game.state))
	_check(float(zwykly["elapsed"]) < 2.0, "zapis bez zaleglosci nie wymysla czasu")

	# Farma zalozona ZANIM gracz cokolwiek wybral nie moze isc na serwer.
	# Po wyczyszczeniu ciasteczek gra zaklada taka farme od razu, a gracz
	# dopiero potem przepisuje kod swojej. Wysylka w tym oknie zasmieca baze.
	Game.new_game()
	Game.state.intro_seen = false
	_check(not Game.may_push_to_cloud(),
			"niepotwierdzona farma startowa nie leci na serwer")
	Game.state.intro_seen = true
	_check(Game.may_push_to_cloud(),
			"po potwierdzeniu ta sama farma juz sie wysyla")

	# Czas plynie tak samo, gdy gracz patrzy i gdy go nie ma. Dawny dzielnik 60
	# dla nieobecnosci zostal usuniety na zyczenie wlasciciela.
	_check(not GameData.balance().get("offline", {}).has("speed_divider"),
			"dzielnika czasu poza gra juz nie ma")
	var scale := GameData.time_scale()
	_check(scale > 0.0 and scale < 1.0, "czas gry plynie wolniej od zegara sciennego")
	_never_event("fox")
	_never_event("disease")
	var away_state := _laying_state(["leghorn"], 1000000.0)
	var live_state := _laying_state(["leghorn"], 1000000.0)
	for bird: Chicken in away_state.chickens + live_state.chickens:
		bird.vaccinated = true
	var window := 2.0 * 3600.0 * scale
	var away_result := Simulation.advance(away_state, window, true)
	var live_result := Simulation.advance(live_state, window)
	_check(int(away_result["eggs_laid"]) == int(live_result["eggs_laid"]),
			"ten sam czas daje tyle samo jaj poza gra co przy graczu (%d i %d)" % [
				int(away_result["eggs_laid"]), int(live_result["eggs_laid"])])
	GameData.reload()
	Game.new_game()


## Rozbudowa kurnika, magazynu i obrony przed lisem.
func _test_buildings() -> void:
	Game.new_game()
	Game.state.money = 1000000.0

	# Kurnik ma pojemnosc, ktorej nie da sie przekroczyc.
	var capacity := Game.state.coop_capacity()
	_check(capacity > 0, "kurnik ma pojemnosc")
	_check(Game.state.coop_occupied() == Game.state.hen_count(), "zajete miejsca to stado")
	Game.state.chickens.clear()
	for i in capacity:
		Game.state.chickens.append(Chicken.create("leghorn"))
	_check(not Game.state.coop_has_room(), "pelny kurnik nie ma miejsca")
	_check(not Game.buy_hen("leghorn"), "do pelnego kurnika nie kupisz kury")

	# Przy pelnym kurniku inkubator odmawia — od wersji 10.1, zeby gracz nie
	# wkladal jaj, ktore i tak nie maja dokad sie wykluc.
	Game.state.eggs = {"leghorn": Game.eggs_per_chick()}
	_check(not Game.can_incubate("leghorn"), "pelny kurnik blokuje wkladanie jaj")
	var waiting := Chick.create("leghorn")
	waiting.grown = waiting.total_seconds()
	Game.state.chicks.append(waiting)
	Simulation.advance(Game.state, 5.0)
	_check(Game.state.chicks.size() == 1, "pisklę czeka, gdy kurnik jest pelny")
	_check(Game.state.hen_count() == capacity, "stado nie przekracza pojemnosci")
	Game.state.chickens.resize(capacity - 1)
	Simulation.advance(Game.state, 2.0)
	_check(Game.state.chicks.is_empty(), "po zwolnieniu miejsca pisklę dolacza do stada")
	_check(Game.state.hen_count() == capacity, "zwolnione miejsce zajmuje odchowana kura")

	var before := Game.state.coop_capacity()
	_check(Game.upgrade_building("coop"), "rozbudowa kurnika udaje sie przy pelnej kasie")
	_finish_build(Game.state, "coop")
	_check(Game.state.coop_capacity() > before, "po rozbudowie miejsc jest wiecej")

	# Magazyn: cena paszy zostaje ta sama (znizka zalezy od opakowania).
	var pack := Game.state.feed_pack()
	var per_kg := float(pack["price"]) / float(pack["size"])
	_check(Game.upgrade_building("storage"), "rozbudowa magazynu udaje sie")
	_finish_build(Game.state, "storage")
	var better := Game.state.feed_pack()
	_check(float(better["size"]) == float(pack["size"]), "ten sam worek")
	_check(is_equal_approx(float(better["price"]) / float(better["size"]), per_kg), "kilogram paszy bez zmian")
	var feed_before := Game.state.feed
	_check(Game.buy_feed(), "zakup paszy dziala po rozbudowie")
	_check(is_equal_approx(Game.state.feed, feed_before + float(better["size"])),
			"do magazynu trafia worek w nowym rozmiarze")

	# Obrona przed lisem.
	_check(is_equal_approx(Game.state.fox_block_chance(), 0.0), "na starcie brak obrony")
	_check(Game.upgrade_building("guard"), "plot da sie postawic")
	var plot_upgrades: Array = GameData.balance().get("buildings", {}).get("guard", {}).get("upgrades", [])
	_check(is_equal_approx(Game.state.fox_block_chance(),
			float(plot_upgrades[0].get("block_chance", -1.0))),
			"pierwszy plot zawraca lisa z szansa z balance.json")
	# Ceny i szanse mozna stroic w balance.json. Pilnujemy tylko, zeby
	# kazdy kolejny plot byl drozszy i lepszy od poprzedniego.
	_check(plot_upgrades.size() == 4, "sa cztery poziomy plotu (jest tyle grafik)")
	for i in plot_upgrades.size():
		var cena := float(plot_upgrades[i].get("price", 0))
		var szansa := float(plot_upgrades[i].get("block_chance", -1.0))
		_check(cena > 0.0, "plot %d cos kosztuje" % (i + 1))
		_check(szansa > 0.0 and szansa <= 1.0, "plot %d: szansa miedzy 0 a 1" % (i + 1))
		if i > 0:
			_check(cena > float(plot_upgrades[i - 1].get("price", 0)),
					"plot %d drozszy od poprzedniego" % (i + 1))
			_check(szansa >= float(plot_upgrades[i - 1].get("block_chance", 0.0)),
					"plot %d nie gorszy od poprzedniego" % (i + 1))

	# Bez pieniedzy nie ma rozbudowy.
	Game.state.money = 0.0
	_check(not Game.upgrade_building("coop"), "bez pieniedzy kurnika nie rozbudujesz")

	# Poziomy przezywaja zapis.
	Game.state.money = 500.0
	SaveGame.save_state(Game.state)
	var loaded := SaveGame.load_state()
	_check(not loaded.is_empty(), "zapis z budynkami sie wczytuje")
	var back: FarmState = loaded["state"]
	_check(back.coop_level == Game.state.coop_level
			and back.storage_level == Game.state.storage_level
			and back.guard_level == Game.state.guard_level, "poziomy budynkow przezywaja zapis")
	_check(back.coop_capacity() == Game.state.coop_capacity(), "pojemnosc po odczycie sie zgadza")
	SaveGame.clear()
	Game.new_game()


## Dowozenie nowych wersji do otwartych kart. Logika decyzji jest czysta,
## wiec da sie ja sprawdzic bez przegladarki. Samo przeladowanie strony
## sprawdza test w prawdziwym Chrome (opisany w PROJECT_STATE.md).
func _test_updater() -> void:
	_check(Updater.parse_version('{"version": "12.14"}') == "12.14", "odczyt version.json")
	_check(Updater.parse_version('{"version": " 12.14 "}') == "12.14", "spacje wokol numeru nie szkodza")
	_check(Updater.parse_version("<html>404</html>") == "", "strona bledu to nie wersja")
	_check(Updater.parse_version('{"inne": 1}') == "", "plik bez pola version to nie wersja")

	_check(Updater.decide("12.14", "12.14", {}) == "none", "ta sama wersja - nic nie robimy")
	_check(Updater.decide("", "12.14", {}) == "none", "brak odpowiedzi - nic nie robimy")
	_check(Updater.decide("12.15", "12.14", {}) == "reload", "nowa wersja - przeladowanie")
	_check(Updater.decide("12.15", "12.14", {"to": "12.15", "attempts": 1}) == "reload",
			"pierwsza nieudana proba - jeszcze raz")
	_check(Updater.decide("12.15", "12.14", {"to": "12.15", "attempts": 2}) == "stuck",
			"druga nieudana proba - koniec przeladowan, prosba o reczne odswiezenie")
	_check(Updater.decide("12.16", "12.14", {"to": "12.15", "attempts": 5}) == "reload",
			"jeszcze nowsza wersja zaczyna liczenie prob od nowa")

	# Po automatycznym przeladowaniu gra nie pyta o kod.
	var bylo := Updater.just_updated
	Updater.just_updated = true
	_check(not Game.should_show_intro(), "po aktualizacji ekran powitalny nie wyskakuje")
	Updater.just_updated = false
	_check(Game.should_show_intro(), "przy zwyklym wejsciu ekran powitalny jest")
	Updater.just_updated = bylo

	# Znacznik: udana aktualizacja go kasuje, nieudana zostawia do liczenia prob.
	var teraz := Time.get_unix_time_from_system()
	Updater._write_flag({"to": GameData.VERSION, "attempts": 1, "at": teraz})
	_check(Updater._consume_flag(), "swiezy znacznik z nasza wersja = wlasnie zaktualizowano")
	_check(Updater._read_flag().is_empty(), "udana aktualizacja kasuje znacznik")
	Updater._write_flag({"to": GameData.VERSION, "attempts": 1, "at": teraz - 3600.0})
	_check(not Updater._consume_flag(), "stary znacznik nie udaje swiezej aktualizacji")
	Updater._write_flag({"to": "99.0", "attempts": 1, "at": teraz})
	_check(not Updater._consume_flag(), "nie doszlismy do wersji 99.0 - to nie aktualizacja")
	_check(int(Updater._read_flag().get("attempts", 0)) == 1,
			"nieudana proba zostaje zapamietana")
	Updater._clear_flag()


## INSTRUKCJA.txt sklada sie z prawdziwych danych gry (tools/gen_instrukcja.py).
## Ten test pilnuje, zeby ktos nie zmienil balansu i nie zapomnial przegenerowac
## instrukcji — inaczej gracz dostaje ceny i pojemnosci sprzed kilku wersji.
##
## Nie sprawdzamy calego tekstu, tylko liczby, ktore gracz naprawde czyta:
## ceny i nazwy wszystkich ras, cel gry, pojemnosci kurnika i limity jaj.
func _test_instrukcja_aktualna() -> void:
	var sciezka := "res://INSTRUKCJA.txt"
	if not FileAccess.file_exists(sciezka):
		_check(false, "INSTRUKCJA.txt lezy w projekcie")
		return
	var tekst := FileAccess.get_file_as_string(sciezka)
	_check(tekst.length() > 4000, "instrukcja nie jest pusta (%d znakow)" % tekst.length())

	_check(tekst.contains("gra w wersji " + GameData.VERSION),
			"instrukcja podaje biezaca wersje gry (%s)" % GameData.VERSION)

	for breed: Dictionary in GameData.breeds():
		var nazwa := tr(String(breed.get("name", "")))
		_check(tekst.contains(nazwa), "instrukcja wymienia rase '%s'" % nazwa)
		_check(tekst.contains(_zl(float(breed.get("price", 0)))),
				"instrukcja zna cene rasy '%s' (%s)"
						% [nazwa, _zl(float(breed.get("price", 0)))])

	var bal := GameData.balance()
	_check(tekst.contains(_zl(float(bal["win"]["money"]))),
			"instrukcja podaje aktualny cel gry")
	_check(tekst.contains(_gr(float(bal["fox"]["scare_taps"]))),
			"instrukcja podaje aktualna liczbe trafien w lisa")
	for upgrade: Dictionary in bal["buildings"]["coop"]["upgrades"]:
		_check(tekst.contains(_gr(float(upgrade["capacity"]))),
				"instrukcja zna pojemnosc kurnika %d" % int(upgrade["capacity"]))
	for upgrade: Dictionary in bal["buildings"]["storage"]["upgrades"]:
		_check(tekst.contains(_gr(float(upgrade["egg_capacity"]))),
				"instrukcja zna limit jaj %d" % int(upgrade["egg_capacity"]))


## Tysiace oddzielone spacja — dokladnie tak, jak sklada je generator.
func _gr(value: float) -> String:
	var text := str(int(round(value)))
	var out := ""
	var count := 0
	for i in range(text.length() - 1, -1, -1):
		out = text[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = " " + out
	return out


func _zl(value: float) -> String:
	return _gr(value) + " zl"


## Teksty: kazdy klucz uzywany przez UI musi miec tlumaczenie, a zadne pole
## nie moze wciagnac sasiednich wierszy.
##
## Ten test powstal po konkretnej wpadce: w opisie rasy uzylem polskiego
## cudzyslowu otwierajacego, ale zamykajacego juz ASCII ("). W pliku CSV
## taki znak konczy pole, wiec cztery kolejne klucze wsiakly w tekst
## o Ayam Cemani i wyswietlily sie graczowi jako gole nazwy.
func _test_strings() -> void:
	var keys: Array[String] = [
		"UNLOCK_TITLE", "UNLOCK_PRICE", "UNLOCK_EGG", "UNLOCK_EGG_HATCH", "UNLOCK_CLOSE",
		"WIN_TITLE", "WIN_MONEY", "WIN_COLLECTION", "WIN_CONTINUE",
		"PANEL_SELL_HEN", "PANEL_CULL_HEN", "PANEL_BUY_HEN",
		"PANEL_UPGRADE_NEXT", "PANEL_UPGRADE_SLIDE", "PANEL_GUARD_NEXT", "PANEL_DOG_NEXT",
		"UPG_COOP_EFFECT", "UPG_STORAGE_EFFECT", "UPG_INCUBATOR_EFFECT",
		"PANEL_COOP_SPACE", "PANEL_FOX_GUARD", "PANEL_LOCKED_PRICE",
		"HINT_FOX_HERE", "HINT_FOX_SCARED", "HINT_COOP_FULL",
	]
	for breed: Dictionary in GameData.breeds():
		keys.append(String(breed.get("name", "")))
		keys.append(String(breed.get("desc", "")))
		keys.append(String(breed.get("lore", "")))
		keys.append(String(breed.get("rarity", "")))
		# 12.20: trzy ciekawostki i malowany portret do okienka nowej rasy.
		var facts: Array = breed.get("facts", [])
		_check(facts.size() == 3, "rasa %s ma trzy ciekawostki" % breed.get("id", ""))
		for fact: Variant in facts:
			keys.append(String(fact))
		var portrait := String(breed.get("portrait", ""))
		_check(portrait.begins_with("res://assets/portraits/") and ResourceLoader.exists(portrait),
				"rasa %s ma malowany portret (%s)" % [breed.get("id", ""), portrait])
	for key: String in ["UNLOCK_CONGRATS", "UNLOCK_FACTS", "GAMEOVER_TITLE", "GAMEOVER_BODY",
			"GAMEOVER_DETAIL", "GAMEOVER_RESTART", "HINT_OUTBREAK_OVER", "HINT_FOX_MASSACRE",
			"PANEL_DISEASE", "PANEL_DISEASE_ON", "PANEL_DISEASE_RISK",
			"REPORT_TITLE", "REPORT_AWAY", "REPORT_EGGS", "REPORT_EGGS_LOST", "REPORT_FOX_VISITS",
			"REPORT_FOX_TOOK", "REPORT_OUTBREAKS", "REPORT_FLOCK", "REPORT_QUIET", "LOG_FOX",
			"LOG_FOX_BLOCKED", "LOG_OUTBREAK", "LOG_OUTBREAK_OVER", "LOG_STORAGE_FULL",
			"LOG_NO_FEED", "LOG_BUILT", "ACH_TITLE", "ACH_COUNT", "ACH_CLOSE", "UNLOCK_CARD_CLOSE",
			"PANEL_MISSING_SHORT"]:
		keys.append(key)
	# FERMA, nie FARMA (wlasciciel 25.11): zaden tekst w grze nie mowi "farma".
	var farma := 0
	var csv := FileAccess.get_file_as_string("res://data/strings.csv")
	for line: String in csv.split("\n"):
		var value := line.substr(line.find(",") + 1).to_lower() if line.contains(",") else ""
		for form: String in ["farma", "farmy", "farmę", "farmie", "farmą", "farmach"]:
			if value.contains(form):
				farma += 1
	_check(farma == 0, "w tekstach gry nie ma slowa 'farma' (%d)" % farma)

	for key: String in keys:
		var text := tr(key)
		_check(text != key, "klucz '%s' ma tlumaczenie" % key)
		_check(not text.contains("\n"), "tekst '%s' nie wciagnal sasiednich wierszy" % key)
		# Wciagniety wiersz zostawia w tekscie wzorzec KLUCZ, — tego nie moze byc.
		_check(not text.contains("_LORE,") and not text.contains("_NAME,")
				and not text.contains("UNLOCK_") and not text.contains("PANEL_"),
				"tekst '%s' nie zawiera golego klucza" % key)

	# Historie ras maja byc czyms wiecej niz jednym zdaniem.
	for breed: Dictionary in GameData.breeds():
		var lore := tr(String(breed.get("lore", "")))
		_check(lore.length() > 120, "historia rasy '%s' jest napisana" % breed.get("id", ""))


## Kod farmy: szesc cyfr, plus stare kody literowo-cyfrowe dla tych, ktorzy
## zalozyli farme przed wersja 8.1.
func _test_farm_code() -> void:
	_check(Cloud.normalize_code("482913") == "482913", "szesc cyfr przechodzi bez zmian")
	_check(Cloud.normalize_code(" 482 913 ") == "482913", "spacje nie przeszkadzaja")
	_check(Cloud.normalize_code("482-913") == "482913", "myslnik nie przeszkadza")
	_check(Cloud.normalize_code("48291") == "", "piec cyfr to za malo")
	_check(Cloud.normalize_code("4829134") == "", "siedem cyfr to za duzo")
	_check(Cloud.normalize_code("") == "", "pusty kod odrzucony")
	_check(Cloud.normalize_code("abcdef") == "", "same litery to nie kod")

	# Wlasny kod gracza musi byc w nowym formacie i przechodzic walidacje.
	_check(Cloud.is_short_code(Cloud.player_id),
			"wlasny kod farmy ma szesc cyfr (jest '%s')" % Cloud.player_id)
	_check(Cloud.normalize_code(Cloud.player_id) == Cloud.player_id, "wlasny kod przechodzi walidacje")
	_check(int(Cloud.player_id) >= Cloud.CODE_MIN, "kod nie zaczyna sie od zera")
	_check(int(Cloud.player_id) <= Cloud.CODE_MAX, "kod miesci sie w zakresie")

	# Stare kody nadal przyjmujemy, zeby nikt nie stracil farmy.
	_check(Cloud.normalize_code("7K73-ABGC-63CK") == "7K73-ABGC-63CK", "stary kod wciaz dziala")
	_check(Cloud.normalize_code("7k73abgc63ck") == "7K73-ABGC-63CK", "stary kod bez myslnikow")
	_check(Cloud.normalize_code("7K73-ABGC") == "", "ucięty stary kod odrzucony")
	_check(not Cloud.is_short_code("7K73-ABGC-63CK"), "stary kod nie udaje nowego")


## 12.18: z jaj wykluwaja sie kurki i kogutki mniej wiecej po polowie
## (incubator.rooster_share), plec przezywa zapis, a podrosniety kogutek
## jest kogutem. Do 12.17 wykluwaly sie same kury.
func _test_hatch_sex() -> void:
	var inc: Dictionary = GameData.balance()["incubator"]
	var stary := float(inc.get("rooster_share", 0.5))
	var koguty := 0
	for i in 600:
		if Chick.roll_rooster():
			koguty += 1
	_check(koguty > 230 and koguty < 370,
			"z 600 piskląt mniej wiecej polowa to kogutki (%d)" % koguty)
	inc["rooster_share"] = 0.0
	var zero := 0
	for i in 200:
		zero += 1 if Chick.roll_rooster() else 0
	_check(zero == 0, "rooster_share 0 = same kurki")
	inc["rooster_share"] = 1.0
	var state := _fresh_state(["leghorn"])
	state.incubating.append(EggBatch.create("leghorn", 1))
	Simulation.advance(state, float(GameData.breed("leghorn")["incubate_seconds"]) + 1.0)
	_check(state.chicks.size() == 1 and state.chicks[0].rooster, "przy 1.0 wykluwa sie kogutek")
	var zapis := SaveGame.to_dict(state)
	var wczytany: FarmState = SaveGame.from_dict(zapis)["state"]
	_check(wczytany.chicks.size() == 1 and wczytany.chicks[0].rooster,
			"plec pisklecia przezywa zapis")
	var koguty_przed := state.rooster_count()
	Simulation.advance(state, float(GameData.breed("leghorn")["grow_seconds"]) + 1.0)
	_check(state.rooster_count() == koguty_przed + 1, "z kogutka wyrasta kogut")
	# Stare zapisy (bez pola "rooster") - pisklę jest kurka.
	var stary_zapis := zapis.duplicate(true)
	for entry: Dictionary in stary_zapis["chicks"]:
		entry.erase("rooster")
	var ze_starego: FarmState = SaveGame.from_dict(stary_zapis)["state"]
	_check(ze_starego.chicks.size() == 1 and not ze_starego.chicks[0].rooster,
			"pisklę ze starego zapisu jest kurka")
	inc["rooster_share"] = stary


## 12.18: lis najpierw czai sie w krzakach i idzie pod plot. Dopiero tam
## plot losuje. Przy grze w tle tej fazy nie ma.
## 12.21 (wlasciciel 25.11): lis ma te sama kostke co godzine w grze i w tle;
## w tle wizyta dzieje sie od razu i lis znika (nie czeka na gracza);
## po przerwie dluzszej niz 3 h gra sklada KRONIKE FERMY z dziennikiem.
func _test_away_fox_and_report() -> void:
	var fox: Dictionary = GameData.balance()["fox"]
	var dis_backup := _snapshot_event("disease")
	_never_event("disease")
	_check(is_equal_approx(float(fox.get("roll_minutes", 0.0)), 60.0), "lis: kostka co godzine")
	var scale := GameData.time_scale()

	# Noc 8 h w tle przy pewnej kostce: lis przychodzi co godzine, nie raz.
	var night := _herd(60)
	_arm_fox(night)
	night.fox_roll_timer = 0.0
	night.dog_level = 1
	fox["kills_min"] = 1
	fox["kills_max"] = 1
	var res := Simulation.advance(night, 8.0 * 3600.0 * scale, true)
	var wizyty := 0
	for entry: Dictionary in res["log"]:
		if entry["kind"] == "fox" or entry["kind"] == "fox_blocked":
			wizyty += 1
	_check(wizyty >= 7 and wizyty <= 9, "w tle lis co godzine: %d wizyt w 8 h" % wizyty)
	_check(night.fox_visit_left <= 0.0 and night.fox_lurk_left <= 0.0,
			"po nadrobieniu lis nie czeka na wybiegu")
	# Kolejnosc i czasy w dzienniku rosna.
	var rosnie := true
	var last := -1.0
	for entry: Dictionary in res["log"]:
		rosnie = rosnie and float(entry["t"]) >= last
		last = float(entry["t"])
	_check(rosnie and last <= 8.0 * 3600.0 + 1.0, "dziennik po kolei, w granicach przerwy")

	# Powrot do gry: licznik kostki NIE jest przeterminowany - lis nie wita
	# gracza w pierwszej sekundzie.
	_check(night.fox_roll_timer < 3600.0, "po nocy kostka lisa nie jest zalegla (%.0f s)" % night.fox_roll_timer)
	var witaj := Simulation.advance(night, 5.0 * scale)
	_check(int(witaj["fox_lurking"]) + int(witaj["fox_arrived"]) == 0 or night.fox_roll_timer < 10.0,
			"pierwsze sekundy po powrocie bez zaleglego lisa")
	_disarm_fox()

	# Kronika: tekst z godzinami zegarka i podsumowaniem.
	Game.new_game()
	var fake := {"eggs_laid": 1234, "eggs_lost": 50, "eggs_spoiled": 0, "hatched": 2, "grown_up": 1,
		"fox_blocked": 1, "fox_took": 6, "died_disease": 3, "died_hunger": 0, "got_sick": 4,
		"out_of_feed": false, "built": ["storage"], "outbreaks": 1,
		"log": [{"t": 60.0, "kind": "fox_blocked"},
			{"t": 3700.0, "kind": "fox", "taken": 6, "massacre": false, "dog": "chased"},
			{"t": 7200.0, "kind": "outbreak", "target": 4},
			{"t": 9000.0, "kind": "outbreak_over", "dead": 3},
			{"t": 9100.0, "kind": "storage_full"},
			{"t": 9200.0, "kind": "built", "id": "storage", "level": 1}]}
	var report := Game.build_away_report(fake, 4.0 * 3600.0, 10)
	_check(int(report["fox_in"]) == 1 and int(report["fox_blocked"]) == 1 and int(report["fox_took"]) == 6,
			"kronika liczy wizyty lisa")
	var lines: Array = report["log"]
	_check(lines.size() == 6, "kronika ma 6 wpisow")
	var godzina := String(lines[1][1])
	_check(godzina.length() == 5 and godzina[2] == ":", "wpis ma godzine zegarka (%s)" % godzina)
	_check(String(lines[1][2]).contains("6") and String(lines[1][2]).contains("Pies"),
			"wpis o lisie mowi ile i co zrobil pies: %s" % lines[1][2])
	_check(String(lines[5][2]).contains("Magazyn"), "wpis o budowie nazywa budynek: %s" % lines[5][2])

	# Game: krotka przerwa bez kroniki, dluga z kronika.
	var hits := [0]
	var on_report := func(_r: Dictionary) -> void: hits[0] += 1
	Events.away_report.connect(on_report)
	# 13.0.1 (wlasciciel 27.11): kronika po kazdym powrocie (od 6 minut).
	Game._apply_elapsed(60.0)
	_check(hits[0] == 0, "minuta przerwy - bez kroniki")
	Game._apply_elapsed(4.0 * 3600.0)
	_check(hits[0] == 1 and not Game.last_away_report.is_empty(), "4 h przerwy - kronika fermy")
	Game._apply_elapsed(600.0)
	_check(hits[0] == 2, "10 minut przerwy - tez kronika")
	Events.away_report.disconnect(on_report)
	Game.last_away_report = {}
	_restore_event("disease", dis_backup)
	Game.new_game()


## GAME OVER: bankructwo tylko wtedy, gdy naprawde nie da sie grac dalej.
func _test_game_over() -> void:
	var per_chick := int(GameData.balance()["incubator"].get("eggs_per_chick", 6))
	var pair := FarmState.hen_buy_price("leghorn") + FarmState.hen_buy_price("leghorn", true)
	Game.new_game()
	_check(not Simulation.check_bankrupt(Game.state), "nowa ferma nie jest bankrutem")

	var empty := FarmState.new()
	empty.money = 0.0
	_check(Simulation.check_bankrupt(empty), "zero ptakow i zero zlotych = bankructwo")
	empty.money = pair
	_check(not Simulation.check_bankrupt(empty), "starczy na pare leghornow = gramy dalej")
	empty.money = pair - 1.0
	_check(Simulation.check_bankrupt(empty), "brakuje zlotowki do pary = bankructwo")
	empty.eggs = {"leghorn": 3}
	empty.money = pair - 1.0
	_check(not Simulation.check_bankrupt(empty), "jaja w magazynie licza sie do gotowki")
	empty.eggs = {"marans": per_chick}
	empty.money = 0.0
	_check(not Simulation.check_bankrupt(empty), "jaja na wyleg ratuja ferme")
	empty.eggs = {}

	var lonely := FarmState.new()
	lonely.chickens.append(Chicken.create("leghorn"))
	lonely.money = FarmState.hen_buy_price("leghorn", true)
	_check(not Simulation.check_bankrupt(lonely), "kura bez koguta, ale stac na koguta")
	lonely.money = 0.0
	_check(Simulation.check_bankrupt(lonely), "kura bez koguta i bez grosza = bankructwo")
	lonely.chicks.append(Chick.create("leghorn", 0.0, true))
	_check(not Simulation.check_bankrupt(lonely), "piskle rosnie - jeszcze nie koniec")
	lonely.chicks.clear()

	var couple := FarmState.new()
	couple.chickens.append(Chicken.create("rhode"))
	couple.chickens.append(Chicken.create_rooster("rhode"))
	_check(not Simulation.check_bankrupt(couple), "para kura + kogut bez grosza to nie bankructwo")
	couple.chickens[0].sick = true
	couple.chickens[1].sick = true
	_check(Simulation.check_bankrupt(couple), "chora para bez grosza = bankructwo (chore i tak padna)")

	# Cudze ptaki do sprzedania tez sie licza.
	var rich_birds := FarmState.new()
	for i in 4:
		rich_birds.chickens.append(Chicken.create("cemani"))
	_check(not Simulation.check_bankrupt(rich_birds), "kury na sprzedaz pozwalaja kupic koguta")

	# Game: zgloszenie raz i restart pod tym samym kodem.
	var hits := [0]
	var on_over := func() -> void: hits[0] += 1
	Events.game_over.connect(on_over)
	var code := Cloud.player_id
	Game.state.chickens.clear()
	Game.state.chicks.clear()
	Game.state.incubating.clear()
	Game.state.eggs = {}
	Game.state.money = 0.0
	Game._check_game_over()
	Game._check_game_over()
	_check(hits[0] == 1, "GAME OVER zgloszone dokladnie raz (%d)" % hits[0])
	Game.restart_after_game_over()
	_check(not Simulation.check_bankrupt(Game.state) and Game.state.hen_count() > 0,
			"restart daje swieza ferme")
	_check(Cloud.player_id == code, "restart zostawia ten sam kod fermy")
	Game._check_game_over()
	_check(hits[0] == 1, "po restarcie nie ma GAME OVER")
	Events.game_over.disconnect(on_over)
	Game.new_game()


## Rzez (wlasciciel 25.11): okolo 5% wejsc lisa wybija CALE stado, ale
## tylko bez psa. Gracz moze go przegonic; w tle dziala bezpiecznik strat.
func _test_fox_massacre() -> void:
	var fox: Dictionary = GameData.balance()["fox"]
	var dis_backup := _snapshot_event("disease")
	_never_event("disease")
	var default_chance := float(_snapshot_event("fox").get("massacre_chance", -1.0))
	_check(is_equal_approx(default_chance, 0.05), "rzez: okolo 5%% wejsc (%.2f)" % default_chance)
	var scale := GameData.time_scale()

	var state := _herd(20)
	_arm_fox(state)
	fox["massacre_chance"] = 1.0
	var wejscie := Simulation.advance(state, 1.0)
	_check(int(wejscie["fox_arrived"]) == 1, "rzez: lis wszedl")
	_check(int(wejscie.get("fox_massacre", 0)) == 1 and state.fox_massacre, "rzez: zgloszona")
	_check(state.fox_kill_left == 19, "rzez: lup to cale stado (%d)" % state.fox_kill_left)
	for i in 60:
		Simulation.advance(state, 2.0 * scale)
		if state.fox_visit_left <= 0.0:
			break
	_check(state.hen_count() == 0, "rzez: bez psa i bez klikania stado wybite (%d)" % state.hen_count())
	_check(state.fox_visit_left <= 0.0 and not state.fox_massacre, "rzez: lis poszedl, flaga zdjeta")

	# Z psem rzezi nie ma, nawet przy pewnej kostce.
	var pies := _herd(20)
	_arm_fox(pies)
	fox["massacre_chance"] = 1.0
	pies.dog_level = 1
	var z_psem := Simulation.advance(pies, 1.0)
	_check(int(z_psem["fox_arrived"]) == 1 and int(z_psem.get("fox_massacre", 0)) == 0
			and not pies.fox_massacre, "z psem lis nie robi rzezi")
	_check(pies.fox_kill_left <= int(fox.get("kills_max", 10)), "z psem zwykly lup")

	# Przegoniony palcem konczy rzez.
	var palec := _herd(20)
	_arm_fox(palec)
	fox["massacre_chance"] = 1.0
	Simulation.advance(palec, 1.0)
	Simulation.fox_leaves(palec)
	_check(not palec.fox_massacre and palec.hen_count() == 19, "przegoniony lis konczy rzez")

	# W tle: lis znika od razu, bez bezpiecznika.
	var tlo := _herd(20)
	_arm_fox(tlo)
	fox["massacre_chance"] = 1.0
	var w_tle := Simulation.advance(tlo, 1.0, true)
	# 12.21: w tle lis nie ma bezpiecznika strat - rzez wybija wszystko.
	_check(int(w_tle["fox_took"]) == 20 and tlo.hen_count() == 0,
			"w tle rzez wybija cale stado (%d)" % int(w_tle["fox_took"]))
	var wpis: Array = w_tle.get("log", [])
	_check(wpis.size() == 1 and wpis[0]["kind"] == "fox" and int(wpis[0]["taken"]) == 20
			and bool(wpis[0]["massacre"]), "rzez w tle trafia do dziennika")
	_disarm_fox()
	_restore_event("disease", dis_backup)


func _test_fox_lurk() -> void:
	var state := _laying_state(["leghorn", "leghorn", "leghorn", "leghorn", "leghorn", "leghorn"])
	_arm_fox(state)
	var fox: Dictionary = GameData.balance()["fox"]
	fox["lurk_min_seconds"] = 6.0
	fox["lurk_max_seconds"] = 6.0
	fox["approach_seconds"] = 2.0
	var scale := GameData.time_scale()
	var wynik := Simulation.advance(state, 1.0)
	_check(int(wynik.get("fox_lurking", 0)) == 1, "po kostce lis najpierw czai sie w krzakach")
	_check(int(wynik["fox_arrived"]) == 0 and int(wynik["fox_took"]) == 0,
			"czajacy sie lis jeszcze nic nie zabral")
	_check(absf(state.fox_lurk_left - 8.0) < 1.0, "czai sie 6 s + 2 s drogi (%.1f)" % state.fox_lurk_left)
	var stado := state.hen_count()
	var w_krzakach := Simulation.advance(state, 5.0 * scale)
	_check(int(w_krzakach["fox_arrived"]) == 0 and state.hen_count() == stado,
			"w trakcie czajenia nic sie nie dzieje")
	_check(int(w_krzakach.get("fox_lurking", 0)) == 0, "drugi lis nie przychodzi w tym czasie")
	var pod_plotem := Simulation.advance(state, 4.0 * scale)
	_check(int(pod_plotem["fox_arrived"]) == 1, "pod plotem (bez plotu) lis wchodzi")
	_check(state.fox_lurk_left <= 0.0, "po wejsciu faza w krzakach skonczona")

	# Plot, ktory zawsze wygrywa: lis zawraca i nic nie zabiera.
	var plot := _laying_state(["leghorn", "leghorn", "leghorn", "leghorn", "leghorn", "leghorn"])
	_arm_fox(plot)
	fox["lurk_min_seconds"] = 3.0
	fox["lurk_max_seconds"] = 3.0
	fox["approach_seconds"] = 1.0
	var guard: Array = GameData.balance()["buildings"]["guard"]["upgrades"]
	var stara_szansa := float(guard[0]["block_chance"])
	guard[0]["block_chance"] = 1.0
	plot.guard_level = 1
	var stado_plot := plot.hen_count()
	Simulation.advance(plot, 1.0)
	_check(plot.fox_lurk_left > 0.0, "z plotem lis tez najpierw sie czai")
	var odbity := Simulation.advance(plot, 6.0 * scale)
	_check(int(odbity["fox_blocked"]) == 1 and int(odbity["fox_arrived"]) == 0,
			"plot rozstrzyga dopiero pod plotem: lis zawrocony")
	_check(plot.hen_count() == stado_plot, "zawrocony lis nic nie zabral")
	guard[0]["block_chance"] = stara_szansa

	# Gra w tle: bez fazy w krzakach, wizyta rozstrzyga sie od razu.
	var tlo := _laying_state(["leghorn", "leghorn", "leghorn", "leghorn", "leghorn", "leghorn"])
	_arm_fox(tlo)
	fox["lurk_min_seconds"] = 6.0
	fox["lurk_max_seconds"] = 6.0
	var w_tle := Simulation.advance(tlo, 5.0, true)
	_check(int(w_tle.get("fox_lurking", 0)) == 0 and tlo.fox_lurk_left <= 0.0,
			"w tle lis sie nie czai")
	_check(int(w_tle["fox_took"]) >= 1, "w tle wizyta rozstrzyga sie od razu")
	# Czajenie nie przechodzi przez zapis (tak jak trwajaca wizyta).
	var czai := _laying_state(["leghorn", "leghorn", "leghorn", "leghorn", "leghorn", "leghorn"])
	czai.fox_lurk_left = 5.0
	_check((SaveGame.from_dict(SaveGame.to_dict(czai))["state"] as FarmState).fox_lurk_left == 0.0,
			"lis w krzakach znika po wczytaniu gry")
	_disarm_fox()


## Blad z 272180 (24.11): lis, ktory sam skonczyl polowanie, zostawal na
## wybiegu, bo do sceny nie lecial zaden sygnal. Teraz symulacja liczy
## "fox_left", a Game wysyla Events.fox_left. Ofiary maja rasy (piora).
func _test_fox_left_and_victims() -> void:
	var state := _laying_state(["marans", "marans", "marans", "marans", "marans", "marans"])
	_arm_fox(state)
	var wejscie := Simulation.advance(state, 1.0)
	_check(int(wejscie["fox_arrived"]) == 1, "lis wszedl (test ofiar)")
	var ofiary: Array = wejscie.get("fox_victims", [])
	_check(ofiary.size() == int(wejscie["fox_took"]) and ofiary.size() >= 1,
			"kazda zabita kura ma rase na liscie ofiar (%d/%d)" % [ofiary.size(), int(wejscie["fox_took"])])
	_check(ofiary.is_empty() or String(ofiary[0]) == "marans", "rasa ofiary sie zgadza")
	state.fox_kill_left = 1
	state.fox_kill_timer = 0.0
	var koniec := Simulation.advance(state, 1.0)
	_check(int(koniec.get("fox_left", 0)) == 1, "lis, ktory zebral lup, odchodzi (fox_left)")
	_check(state.fox_visit_left <= 0.0, "po odejsciu wizyta zamknieta")
	var dostalem := [false]
	var odbior := func() -> void: dostalem[0] = true
	Events.fox_left.connect(odbior)
	Game._report_fox_end({"fox_left": 1})
	Events.fox_left.disconnect(odbior)
	_check(dostalem[0], "Game wysyla do sceny Events.fox_left")
	_check(not GameData.breed("cemani").get("feather_colors", []).is_empty(),
			"cemani ma kolory piór w breeds.json")
	for b: Dictionary in GameData.breeds():
		for hex in b.get("feather_colors", []):
			_check(Color.html_is_valid(String(hex)), "%s: kolor piora %s poprawny" % [b["id"], hex])
	_disarm_fox()


## Konczy budowe prawdziwa sciezka symulacji (bez czekania pol godziny).
func _finish_build(state: FarmState, building_id: String) -> void:
	if not state.is_building(building_id):
		return
	(state.construction[building_id] as Array)[0] = 0.001
	Simulation.advance(state, 1.0)


## 12.19: kurnik, magazyn i inkubator maja po 10 poziomow, a rozbudowa
## trwa od 5 minut do godziny ZEGARA (wlasciciel, 25.11).
func _test_construction() -> void:
	for id: String in ["coop", "storage", "incubator"]:
		var cfg: Dictionary = GameData.balance()["incubator"] if id == "incubator" \
				else GameData.balance()["buildings"][id]
		var ups: Array = cfg.get("upgrades", [])
		_check(ups.size() + 1 == 10, "%s ma 10 poziomow (ma %d)" % [id, ups.size() + 1])
		var names := {}
		var base := String(cfg.get("name", ""))
		_check(not base.strip_edges().is_empty(), "%s: poziom startowy ma nazwe" % id)
		names[base] = true
		var last := 0.0
		for i in ups.size():
			var u: Dictionary = ups[i]
			var nazwa := String(u.get("name", ""))
			_check(not nazwa.strip_edges().is_empty(), "%s poziom %d ma nazwe" % [id, i + 2])
			_check(not names.has(nazwa), "%s: nazwa '%s' sie nie powtarza" % [id, nazwa])
			names[nazwa] = true
			var m := float(u.get("build_minutes", 0))
			_check(m >= 5.0 and m <= 60.0, "%s poziom %d buduje sie 5-60 min (%.1f)" % [id, i + 2, m])
			_check(m > last, "%s poziom %d buduje sie dluzej niz poprzedni" % [id, i + 2])
			last = m
		_check(float(ups[0].get("build_minutes", 0)) == 5.0, "%s: pierwsza rozbudowa 5 min" % id)
		_check(float(ups[-1].get("build_minutes", 0)) == 60.0, "%s: ostatnia rozbudowa godzina" % id)

	Game.new_game()
	var state := Game.state
	var scale := GameData.time_scale()
	state.money = 1000000.0
	state.feed = 100000.0
	var cap := state.coop_capacity()
	var minuty := float(state.upgrade_entry("coop").get("build_minutes", 0))
	var cena := float(state.upgrade_entry("coop").get("price", 0))
	_check(Game.upgrade_building("coop"), "budowa kurnika rusza")
	_check(is_equal_approx(state.money, 1000000.0 - cena), "placi sie od razu")
	_check(state.coop_level == 0 and state.coop_capacity() == cap,
			"w trakcie budowy kurnik ma stary poziom")
	_check(state.is_building("coop"), "kurnik jest w budowie")
	_check(absf(state.construction_left("coop") - minuty * 60.0) < 0.01,
			"budowa trwa %.1f min zegara" % minuty)
	_check(not Game.upgrade_building("coop"), "drugiej budowy tego samego budynku nie da sie zamowic")
	_check(is_equal_approx(state.money, 1000000.0 - cena), "odmowa niczego nie pobiera")
	_check(Game.upgrade_building("storage"), "inny budynek mozna budowac rownolegle")
	_check(Game.upgrade_building("guard"), "plot nie ma czasu budowy")
	_check(state.guard_level == 1 and not state.is_building("guard"), "plot stoi od razu")
	var przed := Simulation.advance(state, (minuty * 60.0 - 30.0) * scale)
	_check((przed.get("built", []) as Array).is_empty() and state.coop_level == 0,
			"pol minuty przed koncem kurnik sie jeszcze buduje")
	_check(state.construction_progress("coop") > 0.85, "postep budowy rosnie")
	var po := Simulation.advance(state, 40.0 * scale)
	_check((po.get("built", []) as Array).has("coop"), "symulacja zglasza skonczona budowe")
	_check(state.coop_level == 1 and not state.is_building("coop"), "po budowie kurnik ma poziom 2")
	# Zapis w trakcie budowy i dokonczenie jej w tle. Magazyn rownolegly
	# skonczyl sie razem z kurnikiem (tyle samo minut), wiec zamawiamy nastepny.
	_check(state.storage_level == 1, "rownolegly magazyn tez skonczony")
	_check(Game.upgrade_building("storage"), "kolejna budowa magazynu rusza")
	_check(state.is_building("storage"), "magazyn sie buduje")
	var zostalo := state.construction_left("storage")
	var wczytany: FarmState = SaveGame.from_dict(SaveGame.to_dict(state))["state"]
	_check(wczytany.is_building("storage") and absf(wczytany.construction_left("storage") - zostalo) < 0.01,
			"budowa przezywa zapis")
	var tlo := Simulation.advance(wczytany, (zostalo + 5.0) * scale, true)
	_check((tlo.get("built", []) as Array).has("storage") and wczytany.storage_level == 2,
			"budowa konczy sie takze w tle")
	var stary := SaveGame.to_dict(state)
	stary.erase("construction")
	var ze_starego: FarmState = SaveGame.from_dict(stary)["state"]
	_check(ze_starego.construction.is_empty(), "stary zapis bez budow wczytuje sie czysto")
	Game.new_game()


## 12.19: wszystkie czasy w czasie ziemskim.
func _test_real_time_texts() -> void:
	_check(NumberFormat.duration(30.0) == "30 s", "30 s")
	_check(NumberFormat.duration(600.0) == "10 min", "10 min")
	_check(NumberFormat.duration(3600.0 * 3 + 300.0) == "3 godz. 5 min", "3 godz. 5 min")
	_check(NumberFormat.duration(86400.0 + 3600.0 * 4) == "1 dzień 4 godz.", "1 dzien")
	_check(NumberFormat.duration(86400.0 * 2) == "2 dni", "2 dni")
	_check(NumberFormat.clock(247.0) == "4:07", "zegar 4:07")
	_check(NumberFormat.clock(3750.0) == "1:02:30", "zegar 1:02:30")
	var csv := FileAccess.get_file_as_string("res://data/strings.csv")
	_check(not csv.contains("na dzień\""), "zadnego 'na dzien' gospodarstwa w napisach")
	_check(not csv.contains("PANEL_DAYS"), "licznik dni gospodarstwa usuniety")
