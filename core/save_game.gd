class_name SaveGame
extends RefCounted
## Zapis i odczyt stanu gry.
##
## Plik lezy w `user://`, czyli tam, gdzie system daje aplikacji miejsce na
## dane. W przegladarce jest to pamiec tej jednej przegladarki na tym jednym
## urzadzeniu — kazdy gracz ma wiec wlasna farme i nikt nie widzi cudzej.
##
## Kazdy zapis ma numer wersji. Gdy format sie zmieni, podnosimy VERSION
## i dopisujemy migracje w `_migrate`, zeby stare zapisy dalo sie wczytac.

const PATH := "user://save.json"
## Numer formatu zapisu. Podnosic przy KAZDEJ zmianie ukladu pol.
const VERSION := 1


## Zapisuje stan. Zwraca false, jesli zapis sie nie powiodl.
static func save_state(state: FarmState, path: String = PATH) -> bool:
	var hens := []
	for hen: Chicken in state.chickens:
		hens.append({"breed": hen.breed_id, "since_last_egg": hen.since_last_egg})
	var data := {
		"version": VERSION,
		"saved_at": Time.get_unix_time_from_system(),
		"money": state.money,
		"eggs": state.eggs,
		"eggs_on_ground": state.eggs_on_ground,
		"feed": state.feed,
		"chickens": hens,
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("SaveGame: nie moge zapisac do %s (blad %d)" % [path, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	return true


static func has_save(path: String = PATH) -> bool:
	return FileAccess.file_exists(path)


static func clear(path: String = PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Wczytuje zapis. Zwraca pusty slownik, jesli zapisu nie ma albo jest
## nieczytelny; w przeciwnym razie {"state": FarmState, "elapsed": sekundy}.
## `elapsed` to czas, ktory uplynal od zapisu — nigdy ujemny, nawet gdy
## zegar urzadzenia cofnie sie miedzy sesjami.
static func load_state(path: String = PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		push_error("SaveGame: zapis %s jest uszkodzony — zaczynam nowa gre" % path)
		return {}

	var data: Dictionary = json.data
	var version := int(data.get("version", 0))
	if version > VERSION:
		push_warning("SaveGame: zapis pochodzi z nowszej wersji gry (%d) — pomijam go" % version)
		return {}
	data = _migrate(data, version)

	var state := FarmState.new()
	state.money = int(data.get("money", 0))
	state.eggs = int(data.get("eggs", 0))
	state.eggs_on_ground = int(data.get("eggs_on_ground", 0))
	state.feed = float(data.get("feed", 0.0))
	for entry: Dictionary in data.get("chickens", []):
		var breed_id := String(entry.get("breed", ""))
		# Rasa mogla zniknac z breeds.json — taka kura przepada, zamiast psuc zapis.
		if GameData.breed(breed_id).is_empty():
			push_warning("SaveGame: pomijam kure nieznanej rasy '%s'" % breed_id)
			continue
		state.chickens.append(Chicken.create(breed_id, float(entry.get("since_last_egg", 0.0))))

	var elapsed := maxf(0.0, Time.get_unix_time_from_system() - float(data.get("saved_at", 0.0)))
	return {"state": state, "elapsed": elapsed}


## Przenosi dane ze starszych formatow do biezacego.
static func _migrate(data: Dictionary, from_version: int) -> Dictionary:
	# Na razie istnieje tylko wersja 1. Kolejne migracje dopisywac tutaj,
	# po kolei, kazda podnoszaca `from_version` o jeden.
	if from_version < 1:
		data["version"] = 1
	return data
