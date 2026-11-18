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
func _fresh_state(hens: Array[String] = ["leghorn"], feed := 100.0) -> FarmState:
	var state := FarmState.new()
	state.money = 100
	state.feed = feed
	for breed_id in hens:
		state.chickens.append(Chicken.create(breed_id))
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
	_check(state.eggs == 0, "brakujace pole = 0")
	_check(state.hen_count() == 2, "hen_count")
	_check(is_equal_approx(state.feed, 20.0), "feed z configu")
	_check(Game.state != null and Game.state.hen_count() == 3, "Game wystartowal z 3 kurami z balance.json")


func _test_data_files() -> void:
	_check(GameData.balance().has("start"), "balance.json ma sekcje start")
	_check(GameData.buildings().size() == 4, "buildings.json ma 4 budynki")
	_check(GameData.breeds().size() == 4, "breeds.json ma 4 rasy")
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
		for key in ["name", "desc"]:
			_check(_has_text(translation, breed.get(key, "")), "tekst %s" % breed.get(key, ""))

	# Kazda rasa z sekcji start musi istniec w breeds.json.
	for breed_id: String in GameData.balance().get("start", {}).get("hens", []):
		_check(not GameData.breed(breed_id).is_empty(), "rasa startowa '%s' istnieje" % breed_id)

	# Teksty uzywane przez panel.
	for key in ["PANEL_HENS", "PANEL_FEED_LEFT", "PANEL_EGGS_STORED", "PANEL_EGGS_WORTH",
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
	var state := _fresh_state()
	var result := Simulation.advance(state, seconds)
	_check(int(result["eggs_laid"]) == 1, "jedna kura, jedno jajko po %.0f s" % seconds)
	_check(state.eggs_on_ground == 1, "jajko wyladowalo na wybiegu")
	_check(state.eggs == 0, "jajko nie trafia od razu do magazynu")

	# Przed czasem nie ma nic.
	var early := _fresh_state()
	_check(int(Simulation.advance(early, seconds - 5.0)["eggs_laid"]) == 0, "przed czasem brak jaja")

	# Trzy kury przez trzy cykle: dziewiec jaj.
	var flock := _fresh_state(["leghorn", "leghorn", "leghorn"])
	_check(int(Simulation.advance(flock, seconds * 3.0)["eggs_laid"]) == 9, "3 kury x 3 cykle = 9 jaj")

	# Pasza sie zuzywa.
	var eating := _fresh_state(["leghorn"], 10.0)
	Simulation.advance(eating, 60.0)
	var expected := 10.0 - float(GameData.breed("leghorn").get("feed_per_minute", 0.0))
	_check(absf(eating.feed - expected) < 0.01, "zuzycie paszy przez minute")

	# Bez paszy nie ma jaj i jest sygnal o braku.
	var hungry := _fresh_state(["leghorn"], 0.0)
	var hungry_result := Simulation.advance(hungry, seconds * 2.0)
	_check(int(hungry_result["eggs_laid"]) == 0, "brak paszy = brak jaj")
	_check(bool(hungry_result["out_of_feed"]), "brak paszy jest raportowany")

	# Wynik nie zalezy od tego, czy liczymy jednym duzym krokiem czy wieloma malymi.
	var big := _fresh_state(["leghorn", "rhode"])
	var small := _fresh_state(["leghorn", "rhode"])
	Simulation.advance(big, 600.0)
	for i in 600:
		Simulation.advance(small, 1.0)
	_check(big.eggs_on_ground == small.eggs_on_ground, "ten sam wynik przy roznych krokach czasu")

	# Pelny wybieg wstrzymuje znoszenie.
	var capacity := int(GameData.balance().get("run", {}).get("max_eggs_on_ground", 24))
	var full := _fresh_state(["leghorn"])
	full.eggs_on_ground = capacity
	_check(int(Simulation.advance(full, seconds * 2.0)["eggs_laid"]) == 0, "pelny wybieg wstrzymuje znoszenie")
	_check(full.eggs_on_ground == capacity, "liczba jaj na wybiegu nie przekracza limitu")


func _test_economy() -> void:
	var economy: Dictionary = GameData.balance().get("economy", {})

	# Zbieranie: z wybiegu do magazynu.
	Game.new_game()
	Game.state.eggs_on_ground = 2
	_check(Game.collect_egg(), "zbieranie jajka udaje sie, gdy jest co zbierac")
	_check(Game.state.eggs == 1 and Game.state.eggs_on_ground == 1, "jajko przeszlo na stan magazynu")
	Game.collect_egg()
	_check(not Game.collect_egg(), "pusty wybieg: nie ma czego zbierac")

	# Sprzedaz.
	Game.new_game()
	Game.state.eggs = 4
	var money_before := Game.state.money
	var earned := Game.sell_eggs()
	_check(earned == 4 * int(GameData.breed("leghorn").get("egg_value", 0)), "zarobek ze sprzedazy 4 jaj")
	_check(Game.state.money == money_before + earned, "pieniadze wzrosly o zarobek")
	_check(Game.state.eggs == 0, "magazyn jaj pusty po sprzedazy")
	_check(Game.sell_eggs() == 0, "sprzedaz bez jaj nic nie daje")

	# Zakup paszy.
	Game.new_game()
	var feed_before := Game.state.feed
	Game.state.money = int(economy.get("feed_pack_price", 0))
	_check(Game.buy_feed(), "zakup paszy za dokladna kwote")
	_check(absf(Game.state.feed - (feed_before + float(economy.get("feed_pack_size", 0)))) < 0.01, "pasza doliczona")
	_check(Game.state.money == 0, "pieniadze pobrane")
	_check(not Game.buy_feed(), "brak pieniedzy blokuje zakup paszy")

	# Zakup kury.
	Game.new_game()
	var hens_before := Game.state.hen_count()
	Game.state.money = int(GameData.breed("rhode").get("price", 0))
	_check(Game.buy_hen("rhode"), "zakup kury za dokladna kwote")
	_check(Game.state.hen_count() == hens_before + 1, "kura dolaczyla do stada")
	_check(Game.state.money == 0, "pieniadze za kure pobrane")
	_check(not Game.buy_hen("rhode"), "brak pieniedzy blokuje zakup kury")
	_check(not Game.buy_hen("nieistniejaca"), "nieznana rasa nie da sie kupic")

	# Wartosc jaj zalezy od stada.
	Game.new_game()
	Game.state.eggs = 1
	_check(Game.state.eggs_value() == int(GameData.breed("leghorn").get("egg_value", 0)),
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
	state.eggs = 5
	state.eggs_on_ground = 3
	state.chickens[0].since_last_egg = 13.0
	_check(SaveGame.save_state(state, path), "zapis sie udaje")

	var loaded := SaveGame.load_state(path)
	_check(not loaded.is_empty(), "odczyt zwraca dane")
	var back: FarmState = loaded["state"]
	_check(back.money == 777, "pieniadze po odczycie")
	_check(back.eggs == 5 and back.eggs_on_ground == 3, "jaja po odczycie")
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
		"money": 5, "eggs": 0, "eggs_on_ground": 0, "feed": 1.0,
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

	# Dwie godziny nieobecnosci przy duzym zapasie paszy.
	var away := _fresh_state(["leghorn"], 10000.0)
	var laid := int(Simulation.advance(away, 7200.0)["eggs_laid"])
	var capacity := int(GameData.balance().get("run", {}).get("max_eggs_on_ground", 24))
	_check(laid == mini(int(7200.0 / seconds), capacity), "produkcja przez 2 godziny z limitem wybiegu")

	# Limit: doba nieobecnosci liczy sie jak `max_hours`, nie jak doba.
	var long_state := _fresh_state(["leghorn"], 10000.0)
	var clamped := clampf(86400.0, 0.0, max_hours * 3600.0)
	_check(clamped == max_hours * 3600.0, "czas offline jest przycinany do limitu")
	Simulation.advance(long_state, clamped)
	_check(long_state.eggs_on_ground <= capacity, "po dlugiej przerwie wybieg nie przekracza limitu")

	# Cofniety zegar nie moze dawac ujemnego postepu.
	var back_in_time := _fresh_state(["leghorn"], 100.0)
	var before := back_in_time.feed
	Simulation.advance(back_in_time, -500.0)
	_check(absf(back_in_time.feed - before) < 0.001, "cofniety zegar niczego nie zmienia")
