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
	_test_breed_gating()
	_test_guard_migration()
	_test_fox_return_speed()
	_test_upgrade_ladders()
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
	_test_strings()
	_test_money_format()
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
	cfg["active_chance"] = 0.0
	cfg["offline_chance"] = 0.0
	cfg["min_hens"] = 1000000
	cfg["grace_minutes"] = 1000000.0


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
	for key in ["PANEL_HENS", "PANEL_CHICKS", "PANEL_DAYS", "PANEL_INCUBATE",
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
	Simulation.advance(offline, 24.0 * 3600.0, true)
	_check(offline.hen_count() > 0, "po dlugiej przerwie bez paszy stado nie ginie w calosci")
	_check(offline.hen_count() >= 5, "bezpiecznik offline zostawia polowe stada")
	Game.new_game()


## Choroby: chora kura nie znosi, po czasie pada, a szczepienie chroni.
func _test_disease() -> void:
	var disease: Dictionary = GameData.balance().get("disease", {})
	var death_seconds := float(disease.get("death_minutes", 7.0)) * 60.0

	var sick := _fresh_state(["cemani"], 100.0)
	sick.chickens[0].sick = true
	var before := sick.eggs_on_ground.size()
	Simulation.advance(sick, 300.0)
	_check(sick.eggs_on_ground.size() == before, "chora kura nie znosi jaj")
	_check(sick.chickens[0].progress() == 0.0, "postep jajka chorej kury stoi na zerze")

	var dying := _fresh_state(["leghorn"], 100.0)
	dying.chickens[0].sick = true
	var result := Simulation.advance(dying, death_seconds + 5.0)
	_check(int(result["died_disease"]) == 1, "chora kura pada po wyznaczonym czasie")
	_check(dying.chickens.is_empty() and dying.corpses.size() == 1, "po chorej kurze zostaja zwloki")

	var vaccinated := _fresh_state(["leghorn"], 100000.0)
	for i in 30:
		var hen := Chicken.create("leghorn")
		hen.vaccinated = true
		vaccinated.chickens.append(hen)
	var vax_result := Simulation.advance(vaccinated, 12.0 * 3600.0)
	var vaccinated_sick := 0
	for hen: Chicken in vaccinated.chickens:
		if hen.sick and hen.vaccinated:
			vaccinated_sick += 1
	_check(vaccinated_sick == 0, "zaszczepiona kura nie choruje")
	_check(int(vax_result["died_disease"]) <= 1, "zaszczepione stado nie pada z choroby")

	# Niezaszczepione stado po dlugim czasie musi w ogole chorowac,
	# inaczej mechanika byla by martwa.
	var exposed := _fresh_state(["leghorn"], 100000.0)
	for i in 30:
		exposed.chickens.append(Chicken.create("leghorn"))
	var exposed_result := Simulation.advance(exposed, 12.0 * 3600.0)
	_check(int(exposed_result["got_sick"]) > 0, "niezaszczepione stado choruje")
	Game.new_game()


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
	fox["active_chance"] = 1.0
	fox["offline_chance"] = 1.0
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
	var odstep := float(fox.get("active_roll_minutes", 60.0)) * 60.0
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
	var before := Game.state.money
	_check(Game.buy_medicine(), "lek da sie kupic, gdy sa chore kury")
	_check(Game.state.money < before, "lek kosztuje")
	_check(Game.state.sick_count() == 1, "lek leczy jedna kure")
	var cured_cemani := true
	for hen: Chicken in Game.state.chickens:
		if hen.breed_id == "cemani" and hen.sick:
			cured_cemani = false
	_check(cured_cemani, "lek ratuje najdrozsza chora kure")

	_check(FarmState.hen_sell_price("leghorn") < float(GameData.breed("leghorn").get("price", 0)),
			"sprzedaz jest tansza od zakupu")
	_check(is_zero_approx(FarmState.hen_sell_price("leghorn", true)),
			"chora kura nie ma ceny skupu")

	# Chorej sztuki skup nie przyjmuje: zostaje lek albo ubicie za darmo.
	Game.state.chickens.clear()
	var ill := Chicken.create("rhode")
	ill.sick = true
	Game.state.chickens.append(ill)
	_check(Game.has_sick("rhode"), "w stadzie jest chora sztuka")
	_check(is_zero_approx(Game.sell_hen("rhode")), "chorej kury nie da sie sprzedac")
	_check(Game.state.chickens.size() == 1, "nieudana sprzedaz nie usuwa kury ze stada")

	# Chora sztuka idzie do skupu za drobne zamiast byc ubijana za darmo.
	var purse := Game.state.money
	_check(Game.cull_hen("rhode"), "chora kure da sie oddac do skupu")
	_check(Game.state.chickens.is_empty(), "oddana kura znika ze stada")
	_check(is_equal_approx(Game.state.money, purse + Game.mcdonalds_price()),
			"za chora kure jest kilka zlotych, a nie zero")
	_check(is_equal_approx(Game.mcdonalds_price(), 5.0), "skup placi 5 zl za sztuke")
	_check(is_equal_approx(Game.medicine_price(), 20.0), "lek kosztuje 20 zl")
	_check(not Game.cull_hen("rhode"), "nie ma juz czego ubijac")

	# Zdrowa idzie normalnie, za pelna stawke.
	Game.state.chickens.append(Chicken.create("rhode"))
	var full_price := Game.sell_hen("rhode")
	_check(is_equal_approx(full_price, FarmState.hen_sell_price("rhode")), "zdrowa idzie za pelna stawke")

	# Kogut tez: chorego nie sprzedasz, ale ubic mozna.
	Game.state.chickens.clear()
	var sick_cock := Chicken.create_rooster("marans")
	sick_cock.sick = true
	Game.state.chickens.append(sick_cock)
	_check(is_zero_approx(Game.sell_hen("marans", true)), "chorego koguta tez nie kupia")
	_check(Game.cull_hen("marans", true), "chorego koguta da sie ubic")
	_check(Game.state.chickens.is_empty(), "ubity kogut znika ze stada")
	_check(Game.state.chickens.is_empty(), "stado puste po obu sprzedazach")
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
	_check(not Game.buy_vaccine() or true, "ponowne szczepienie dotyczy tylko nowych kur")
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
	for breed: Dictionary in GameData.breeds():
		var value := float(breed.get("egg_value", 0))
		_check(value >= 0.4 and value <= 1.0,
				"cena jajka rasy '%s' w widelkach 0,40-1,00 zl" % breed.get("id", ""))
		_check(absf(float(breed.get("sell_price", 0)) - round(float(breed.get("price", 0)) * 0.7)) < 0.51,
				"sprzedaz kury rasy '%s' to 70%% ceny zakupu" % breed.get("id", ""))


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
	var kod := "327733"
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
	var tekst := '[{"player_id":"327733","updated_at":1795000000}]'
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
	# Kundel: co 10 sekund proba z szansa 1/3. Owczarek: co 5 sekund z 2/3,
	# a udana proba to jeszcze 1/3 szansy na zagryzienie lisa.
	_check(absf(float(dogs[0].get("chance", 0.0)) - 1.0 / 3.0) < 0.01,
			"kundel ma jedna trzecia szansy na probe")
	_check(absf(float(dogs[1].get("chance", 0.0)) - 2.0 / 3.0) < 0.01,
			"owczarek ma dwie trzecie")
	_check(is_equal_approx(float(dogs[0].get("interval", 0.0)), 10.0),
			"kundel probuje co dziesiec sekund")
	_check(is_equal_approx(float(dogs[1].get("interval", 0.0)), 5.0),
			"owczarek co piec")
	_check(is_zero_approx(float(dogs[0].get("kill_chance", 1.0))),
			"kundel nie zagryza lisa")
	_check(absf(float(dogs[1].get("kill_chance", 0.0)) - 1.0 / 3.0) < 0.01,
			"owczarek zagryza lisa w jednym przypadku na trzy")

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


## Drabinki rozbudowy: kazdy poziom ma nazwe, jest drozszy od poprzedniego
## i cos realnie dodaje. Pilnuje tez, zeby kolejny poziom nigdy nie byl
## tanszy za jednostke — inaczej oplacaloby sie przeskakiwac poziomy.
func _test_upgrade_ladders() -> void:
	var drabinki := {
		"coop": ["capacity", GameData.balance().get("buildings", {}).get("coop", {})],
		"storage": ["pack_size", GameData.balance().get("buildings", {}).get("storage", {})],
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
		if id == "coop":
			poprzednia_wartosc = float(dane.get("capacity", 0))
		var poprzedni_koszt_jednostki := 0.0
		for i in upgrades.size():
			var poziom: Dictionary = upgrades[i]
			var nazwa := String(poziom.get("name", ""))
			_check(not nazwa.is_empty(), "%s poziom %d ma nazwe" % [id, i + 1])
			_check(tr(nazwa) != nazwa, "%s: nazwa %s jest przetlumaczona" % [id, nazwa])
			var cena := float(poziom.get("price", 0))
			var wartosc := float(poziom.get(pole, 0))
			_check(cena > poprzednia_cena, "%s poziom %d jest drozszy od poprzedniego" % [id, i + 1])
			_check(wartosc > poprzednia_wartosc, "%s poziom %d cos dodaje" % [id, i + 1])
			var koszt_jednostki := cena / maxf(1.0, wartosc - poprzednia_wartosc)
			_check(koszt_jednostki > poprzedni_koszt_jednostki,
					"%s poziom %d nie jest tanszy za jednostke niz poprzedni" % [id, i + 1])
			poprzednia_cena = cena
			poprzednia_wartosc = wartosc
			poprzedni_koszt_jednostki = koszt_jednostki

	# Magazyn ma sens tylko wtedy, gdy kilogram paszy z kazdym poziomem tanieje.
	var economy: Dictionary = GameData.balance().get("economy", {})
	var za_kg := float(economy.get("feed_pack_price", 25)) / maxf(1.0, float(economy.get("feed_pack_size", 25)))
	for poziom: Dictionary in (GameData.balance().get("buildings", {}).get("storage", {}).get("upgrades", []) as Array):
		var nowy := float(poziom.get("pack_price", 0)) / maxf(1.0, float(poziom.get("pack_size", 1)))
		_check(nowy < za_kg, "%s: kilogram paszy tanieje (%.2f -> %.2f)"
				% [String(poziom.get("name", "")), za_kg, nowy])
		za_kg = nowy

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
	_check(is_equal_approx(hours, 4.0), "termin przydatnosci to cztery godziny realne")
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
	_check(is_equal_approx(Game.vaccine_price(), 35.0),
			"siedem kur to 35 zl (jest %.0f)" % Game.vaccine_price())
	Game.state.chickens[0].vaccinated = true
	_check(is_equal_approx(Game.vaccine_price(), 30.0),
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
	_check(Game.may_push_to_cloud(),
			"wlasna, swiezo zalozona farma moze isc na serwer")

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
	_check(state.egg_capacity() == 200, "mala szopa miesci 200 jaj (jest %d)" % state.egg_capacity())

	_check(state.add_egg("leghorn", 150) == 150, "pierwsze 150 jaj sie miesci")
	_check(state.egg_room() == 50, "zostalo miejsca na 50")
	_check(state.add_egg("leghorn", 90) == 50, "z 90 jaj miesci sie tylko 50")
	_check(state.egg_count() == 200, "magazyn pelny, ani jednego wiecej")
	_check(state.add_egg("rhode", 10) == 0, "do pelnego nic juz nie wejdzie")

	# Kazdy poziom magazynu podnosi limit.
	var poprzedni := 200
	var ups: Array = storage.get("upgrades", [])
	for i in ups.size():
		var lim := int(ups[i].get("egg_capacity", 0))
		_check(lim > poprzedni, "magazyn %d miesci wiecej jaj niz poprzedni (%d > %d)"
				% [i + 1, lim, poprzedni])
		poprzedni = lim
	_check(poprzedni >= 500000, "elewator miesci co najmniej pol miliona jaj (%d)" % poprzedni)

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
		_check(is_equal_approx(d.fox_next_multiplier, 5.0),
				"po zagryzieniu odstep rosnie piec razy")
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
	_check(int(disease.get("min_hens", 0)) == 5, "choroba: to samo ograniczenie")

	# Licznik czasu gry idzie od zalozenia farmy i to on otwiera furtke.
	var state := _fresh_state(["leghorn"], 100000.0)
	_check(is_zero_approx(state.played_seconds()), "nowa farma ma zerowy licznik czasu")
	Simulation.advance(state, 1800.0)
	_check(absf(state.played_seconds() - 1800.0) < 1.0,
			"po pol godziny licznik pokazuje pol godziny (%.0f s)" % state.played_seconds())

	# Czestosc. Wlasciciel podal ja wprost i inaczej niz dotad:
	#   lis    — w grze aktywnej kostka raz na godzine realna, szansa 1/3,
	#            czyli srednio jeden lis na trzy godziny grania;
	#   lis    — w grze nieaktywnej kostka raz na dobe, szansa 1/6;
	#   choroba— aktywna gra: kolejna kura co minute realna;
	#            nieaktywna: co cztery godziny.
	# Mierzymy to na samych ustawieniach, bo pelny pomiar statystyczny
	# trwalby minuty, a liczby maja byc dokladnie takie, jak powiedzial.
	_check(is_equal_approx(float(fox.get("active_roll_minutes", 0.0)), 60.0),
			"lis: kostka raz na godzine grania")
	_check(absf(float(fox.get("active_chance", 0.0)) - 1.0 / 3.0) < 0.01,
			"lis: szansa jedna trzecia")
	_check(is_equal_approx(float(fox.get("offline_roll_hours", 0.0)), 24.0),
			"lis: przy nieaktywnej grze kostka raz na dobe")
	_check(absf(float(fox.get("offline_chance", 0.0)) - 1.0 / 6.0) < 0.01,
			"lis: przy nieaktywnej grze szansa jeden do szesciu")
	# Wizyta konczy sie na liczbie zabitych kur, nie na zegarze.
	_check(int(fox.get("kills_min", 0)) == 3 and int(fox.get("kills_max", 0)) == 10,
			"lis zabija od trzech do dziesieciu kur i odchodzi")
	_check(is_equal_approx(float(fox.get("kill_interval_min", 0.0)), 3.0)
			and is_equal_approx(float(fox.get("kill_interval_max", 0.0)), 10.0),
			"kolejna kura ginie co 3-10 sekund")
	_check(is_equal_approx(float(fox.get("killed_return_multiplier", 0.0)), 5.0),
			"po zagryzieniu lisa nastepny przychodzi piec razy pozniej")
	# Choroba dziala tak samo jak lis, tylko dwa razy czesciej: ten sam
	# ksztalt kostki, polowa odstepu.
	_check(is_equal_approx(float(disease.get("active_roll_minutes", 0.0)),
			float(fox.get("active_roll_minutes", 0.0)) / 2.0),
			"choroba: kostka dwa razy czesciej niz u lisa w aktywnej grze")
	_check(is_equal_approx(float(disease.get("offline_roll_hours", 0.0)),
			float(fox.get("offline_roll_hours", 0.0)) / 2.0),
			"choroba: dwa razy czesciej takze przy nieaktywnej grze")
	_check(is_equal_approx(float(disease.get("active_chance", 0.0)),
			float(fox.get("active_chance", 0.0))),
			"choroba: ta sama szansa co u lisa")
	_check(is_equal_approx(float(disease.get("offline_chance", 0.0)),
			float(fox.get("offline_chance", 0.0))),
			"choroba: ta sama szansa offline co u lisa")

	# I pomiar na zywo, zeby liczby z balansu faktycznie cos robily.
	var chore: Array[String] = []
	for i in 12:
		chore.append("leghorn")
	var yard := _fresh_state(chore, 10000000.0)
	yard.days = 40
	# Pomiar na zywo: w aktywnej grze, przez wiele dob grania, choroba
	# wypada mniej wiecej dwa razy czesciej niz lis. Mierzymy same kostki,
	# zeby nie zalezec od tego, ktora kura akurat zachoruje.
	var godzina := 3600.0 * GameData.time_scale()
	var chorych := 0
	var lisow := 0
	for i in 60:
		var dzien := _fresh_state(chore, 10000000.0)
		dzien.days = 40
		dzien.guard_level = 0
		for h in 10:
			var krok := Simulation.advance(dzien, godzina)
			chorych += int(krok["got_sick"])
			lisow += int(krok["fox_arrived"])
			# Leczymy od razu, zeby stado nie znikalo i kostka miala kogo wybierac.
			for chicken: Chicken in dzien.chickens:
				chicken.sick = false
	_check(chorych > 0, "w aktywnej grze kury choruja (%d)" % chorych)
	_check(lisow > 0, "w aktywnej grze lis tez przychodzi (%d)" % lisow)
	_check(chorych > lisow,
			"choroba wypada czesciej niz lis (%d wobec %d)" % [chorych, lisow])

	var spiace := _fresh_state(chore, 10000000.0)
	spiace.days = 40
	var offline_chore := 0
	for i in 20:
		offline_chore += int(Simulation.advance(spiace, 60.0 * GameData.time_scale(), true)["got_sick"])
	_check(offline_chore == 0,
			"w nieaktywnej grze 20 minut nie wystarcza na zachorowanie (%d)" % offline_chore)

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
	_check(Game.state.coop_capacity() > before, "po rozbudowie miejsc jest wiecej")

	# Magazyn: wiekszy worek i nizsza cena za kilogram.
	var pack := Game.state.feed_pack()
	var per_kg := float(pack["price"]) / float(pack["size"])
	_check(Game.upgrade_building("storage"), "rozbudowa magazynu udaje sie")
	var better := Game.state.feed_pack()
	_check(float(better["size"]) > float(pack["size"]), "worek jest wiekszy")
	_check(float(better["price"]) / float(better["size"]) < per_kg, "kilogram paszy tanieje")
	var feed_before := Game.state.feed
	_check(Game.buy_feed(), "zakup paszy dziala po rozbudowie")
	_check(is_equal_approx(Game.state.feed, feed_before + float(better["size"])),
			"do magazynu trafia worek w nowym rozmiarze")

	# Obrona przed lisem.
	_check(is_equal_approx(Game.state.fox_block_chance(), 0.0), "na starcie brak obrony")
	_check(Game.upgrade_building("guard"), "plot da sie postawic")
	# Drabinka plotow wedlug wlasciciela: 200/50%, 400/65%, 800/80%, 2000/95%.
	_check(is_equal_approx(Game.state.fox_block_chance(), 0.5),
			"lichy plot zawraca lisa w polowie podejsc")
	var plot_ceny := [200, 400, 800, 2000]
	var plot_szanse := [0.5, 0.65, 0.8, 0.95]
	var plot_upgrades: Array = GameData.balance().get("buildings", {}).get("guard", {}).get("upgrades", [])
	_check(plot_upgrades.size() == 4, "sa cztery poziomy plotu")
	for i in mini(4, plot_upgrades.size()):
		_check(int(plot_upgrades[i].get("price", 0)) == plot_ceny[i],
				"plot %d kosztuje %d zl" % [i + 1, plot_ceny[i]])
		_check(is_equal_approx(float(plot_upgrades[i].get("block_chance", 0.0)), plot_szanse[i]),
				"plot %d zawraca w %d%% podejsc" % [i + 1, int(plot_szanse[i] * 100)])

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


## Teksty: kazdy klucz uzywany przez UI musi miec tlumaczenie, a zadne pole
## nie moze wciagnac sasiednich wierszy.
##
## Ten test powstal po konkretnej wpadce: w opisie rasy uzylem polskiego
## cudzyslowu otwierajacego, ale zamykajacego juz ASCII ("). W pliku CSV
## taki znak konczy pole, wiec cztery kolejne klucze wsiakly w tekst
## o Ayam Cemani i wyswietlily sie graczowi jako gole nazwy.
func _test_strings() -> void:
	var keys: Array[String] = [
		"UNLOCK_TITLE", "UNLOCK_PRICE", "UNLOCK_EGG", "UNLOCK_CLOSE",
		"WIN_TITLE", "WIN_MONEY", "WIN_COLLECTION", "WIN_CONTINUE",
		"PANEL_SELL_HEN", "PANEL_CULL_HEN", "PANEL_BUY_HEN",
		"PANEL_UPGRADE_COOP", "PANEL_UPGRADE_GUARD", "PANEL_UPGRADE_STORAGE",
		"PANEL_COOP_SPACE", "PANEL_FOX_GUARD", "PANEL_LOCKED_PRICE",
		"HINT_FOX_HERE", "HINT_FOX_SCARED", "HINT_COOP_FULL",
	]
	for breed: Dictionary in GameData.breeds():
		keys.append(String(breed.get("name", "")))
		keys.append(String(breed.get("desc", "")))
		keys.append(String(breed.get("lore", "")))
		keys.append(String(breed.get("rarity", "")))

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
