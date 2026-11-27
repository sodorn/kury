class_name GameData
extends RefCounted
## Dane gry wczytane z res://data/*.json.
##
## Dostep statyczny, bez autoloadu: dziala tak samo w grze, w testach
## uruchamianych przez `-s` i w edytorze. Balans zmienia sie w plikach JSON,
## nie w kodzie.

const DATA_DIR := "res://data/"

## Numer wersji gry. Jedno miejsce do podbicia przy wydaniu — pokazuje sie
## na ekranie powitalnym, zeby bylo widac, czy przegladarka wczytala nowa
## wersje, czy podsunela stara z pamieci.
const VERSION := "13.0.5"

static var _balance: Dictionary = {}
static var _buildings: Array = []
static var _breeds: Array = []
static var _loaded := false


## Sekcje balansu gry ("start", "economy", "run").
static func balance() -> Dictionary:
	_ensure_loaded()
	return _balance


## Lista definicji budynkow z data/buildings.json.
static func buildings() -> Array:
	_ensure_loaded()
	return _buildings


## Definicja budynku o podanym id; pusty slownik, jesli nie ma takiego wpisu.
static func building(id: String) -> Dictionary:
	for def: Dictionary in buildings():
		if def.get("id", "") == id:
			return def
	return {}


## Lista ras kur z data/breeds.json.
static func breeds() -> Array:
	_ensure_loaded()
	return _breeds


## Definicja rasy o podanym id; pusty slownik, jesli nie ma takiego wpisu.
static func breed(id: String) -> Dictionary:
	for def: Dictionary in breeds():
		if def.get("id", "") == id:
			return def
	return {}


## Ile sekund gry przypada na sekunde zegara sciennego. Jedna skala na
## wszystko: granie i nieobecnosc licza sie tak samo.
static func time_scale() -> float:
	return clampf(float(balance().get("offline", {}).get("scale", 1.0)), 0.001, 10.0)


## Wymusza ponowne wczytanie plikow (uzywane w testach).
static func reload() -> void:
	_loaded = false
	_ensure_loaded()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_balance = _load_json("balance.json", {})
	for problem in apply_upgrades(_balance, _load_json("rozbudowy.json", {})):
		push_error("GameData: rozbudowy.json: %s" % problem)
	_buildings = _load_json("buildings.json", [])
	_breeds = _load_json("breeds.json", [])


## ROZBUDOWY (12.22, wlasciciel 25.11): wszystkie poziomy budynkow - nazwy,
## ceny, czasy budowy i to, co daja - siedza w jednym pliku do recznej edycji,
## data/rozbudowy.json, z polskimi kluczami. Tu przepisujemy go na uklad, ktory
## zna reszta kodu (balance.buildings.*, balance.incubator, economy.feed_pack_*),
## wiec logika gry sie nie zmienia. Nazwy poziomow sa zwyklym tekstem, nie
## kluczami tlumaczen - tr() zwraca je bez zmian. Zwraca liste problemow
## (pusta = plik w porzadku); testy pilnuja, zeby byla pusta.
static func apply_upgrades(bal: Dictionary, file: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	var buildings: Dictionary = bal.get_or_add("buildings", {})
	var economy: Dictionary = bal.get_or_add("economy", {})
	var incubator: Dictionary = bal.get_or_add("incubator", {})
	var per_chick := maxi(1, int(incubator.get("eggs_per_chick", 3)))

	var coop: Array = _levels(file, "kurnik", 0, problems)
	if not coop.is_empty():
		var cfg: Dictionary = buildings.get_or_add("coop", {})
		cfg["name"] = String(coop[0].get("nazwa", ""))
		cfg["capacity"] = int(coop[0].get("miejsc", 20))
		cfg["upgrades"] = coop.slice(1).map(func(lv: Dictionary) -> Dictionary:
			return _common(lv).merged({"capacity": int(lv.get("miejsc", 0))}))

	var store: Array = _levels(file, "magazyn", 0, problems)
	if not store.is_empty():
		var cfg: Dictionary = buildings.get_or_add("storage", {})
		cfg["name"] = String(store[0].get("nazwa", ""))
		cfg["egg_capacity"] = int(store[0].get("jaj", 200))
		# Pasza (wlasciciel 25.11): cena za kg zalezy od WIELKOSCI opakowania
		# (znizka_proc), a nie od magazynu.
		var base_kg := float(file.get("pasza_zl_kg", 2.0))
		economy["feed_price_kg"] = base_kg
		var options: Array = []
		for opt: Variant in file.get("pasza_do_kupienia", []):
			if opt is Dictionary and float((opt as Dictionary).get("kg", 0)) > 0.0:
				var off := clampf(float(opt.get("znizka_proc", 0)), 0.0, 100.0)
				options.append({"unit": String(opt.get("nazwa", "worek")), "size": float(opt.get("kg", 0)),
						"discount": off / 100.0, "per_kg": base_kg * (1.0 - off / 100.0)})
		if options.is_empty():
			problems.append("brak listy 'pasza_do_kupienia' (nazwa, kg, znizka_proc)")
			options = [{"unit": "worek", "size": 20.0, "discount": 0.0, "per_kg": base_kg}]
		economy["feed_options"] = options
		# Stare pola dla zgodnosci: pierwszy przycisk.
		economy["feed_pack_size"] = float(options[0]["size"])
		economy["feed_pack_price"] = float(options[0]["size"]) * float(options[0]["per_kg"])
		cfg["upgrades"] = store.slice(1).map(func(lv: Dictionary) -> Dictionary:
			return _common(lv).merged({"egg_capacity": int(lv.get("jaj", 0))}))

	var incu: Array = _levels(file, "inkubator", 0, problems)
	if not incu.is_empty():
		incubator["name"] = String(incu[0].get("nazwa", ""))
		incubator["slots"] = maxi(1, floori(float(incu[0].get("jaj", 9)) / per_chick))
		incubator["eggs"] = int(incu[0].get("jaj", 9))
		incubator["upgrades"] = incu.slice(1).map(func(lv: Dictionary) -> Dictionary:
			return _common(lv).merged({
				"slots": maxi(1, floori(float(lv.get("jaj", 0)) / per_chick)),
				"eggs": int(lv.get("jaj", 0)),
			}))

	var fence: Array = _levels(file, "plot", 1, problems)
	if not fence.is_empty():
		var cfg: Dictionary = buildings.get_or_add("guard", {})
		cfg["upgrades"] = fence.map(func(lv: Dictionary) -> Dictionary:
			return {
				"name": String(lv.get("nazwa", "")),
				"price": float(lv.get("cena", 0)),
				"block_chance": clampf(float(lv.get("lis_zawraca_proc", 0)) / 100.0, 0.0, 1.0),
			})

	var dogs: Array = _levels(file, "pies", 1, problems)
	if not dogs.is_empty():
		var cfg: Dictionary = buildings.get_or_add("dog", {})
		cfg["upgrades"] = dogs.map(func(lv: Dictionary) -> Dictionary:
			return {
				"name": String(lv.get("nazwa", "")),
				"price": float(lv.get("cena", 0)),
				"interval": maxf(0.1, float(lv.get("probuje_co_s", 10))),
				"chance": clampf(float(lv.get("przegania_proc", 0)) / 100.0, 0.0, 1.0),
				"kill_chance": clampf(float(lv.get("zagryza_proc", 0)) / 100.0, 0.0, 1.0),
				"deaf_chance": clampf(float(lv.get("nie_slyszy_proc", 0)) / 100.0, 0.0, 1.0),
				"quit_chance": clampf(float(lv.get("tchorzy_proc", 0)) / 100.0, 0.0, 1.0),
				"quit_after": maxf(0.0, float(lv.get("tchorzy_po_s", 0))),
				"damage_min": maxi(1, int(lv.get("obrazenia_min", 5))),
				"damage_max": maxi(1, int(lv.get("obrazenia_max", 5))),
				"life_days_min": maxf(0.1, float(lv.get("zyje_dni_min", 10))),
				"life_days_max": maxf(0.1, float(lv.get("zyje_dni_max", 10))),
			})
	return problems


## Lista poziomow z pliku rozbudow, sprawdzona: kolejne numery od `first`,
## kazdy z nazwa i nieujemna cena. Bledne wpisy trafiaja do `problems`.
static func _levels(file: Dictionary, key: String, first: int, problems: Array[String]) -> Array:
	var raw: Variant = file.get(key, [])
	if not raw is Array or (raw as Array).is_empty():
		problems.append("brak listy '%s'" % key)
		return []
	var out: Array = []
	for i in (raw as Array).size():
		var lv: Variant = (raw as Array)[i]
		if not lv is Dictionary:
			problems.append("%s: wpis %d nie jest w klamrach {}" % [key, i])
			return []
		var entry: Dictionary = lv
		if int(entry.get("poziom", -1)) != first + i:
			problems.append("%s: wpis %d ma poziom %s, a powinien %d" % [
				key, i, str(entry.get("poziom", "?")), first + i])
		if String(entry.get("nazwa", "")).strip_edges().is_empty():
			problems.append("%s poziom %d: brak nazwy" % [key, first + i])
		if float(entry.get("cena", 0)) < 0.0:
			problems.append("%s poziom %d: ujemna cena" % [key, first + i])
		out.append(entry)
	return out


## Wspolne pola poziomu budynku: nazwa, cena, czas budowy.
static func _common(lv: Dictionary) -> Dictionary:
	return {
		"name": String(lv.get("nazwa", "")),
		"price": float(lv.get("cena", 0)),
		"build_minutes": float(lv.get("budowa_min", 0)),
	}


static func _load_json(file_name: String, fallback: Variant) -> Variant:
	var path := DATA_DIR + file_name
	if not FileAccess.file_exists(path):
		push_error("GameData: brak pliku %s" % path)
		return fallback
	var json := JSON.new()
	var err := json.parse(FileAccess.get_file_as_string(path))
	if err != OK:
		push_error("GameData: blad w %s (linia %d): %s" % [path, json.get_error_line(), json.get_error_message()])
		return fallback
	if typeof(json.data) != typeof(fallback):
		push_error("GameData: nieoczekiwany typ danych w %s" % path)
		return fallback
	return json.data
